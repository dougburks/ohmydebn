#!/bin/bash
#
# Unit tests for bin/ohmydebn-require-systemd and the apps that need it,
# Tailscale and Cloudflare WARP: their services start only under systemd,
# so on Devuan, LCOS and MX Linux with sysvinit Tailscale's installer
# failed at its last step and WARP opened to "Unable to connect". Now the
# installers stop first, saying why, and the launchers open the installer's
# window rather than an app that can't connect. The systemd signal
# directory comes from OHMYDEBN_TEST_SYSTEMD_DIR (the launchers' is
# sed-patched); dpkg answers from MOCK_INSTALLED; sudo, the removers and
# the floating terminals only log.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-require-systemd, and Tailscale and WARP without systemd ==="

setup() {
  mock_init
  SYSTEMD_DIR="$MOCK_DIR/run/systemd/system"
  [ "${MOCK_SYSTEMD:-true}" = true ] && mkdir -p "$SYSTEMD_DIR"
  mock_bin dpkg <<'STUB'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]]
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
case "$*" in *tee*) cat >/dev/null ;; esac
exit 0
STUB
  mock_bin curl <<'STUB'
#!/bin/bash
mock_log "curl $*"
STUB
  local stub
  for stub in ohmydebn-tailscale-remove ohmydebn-cloudflare-warp-remove ohmydebn-launch-floating-terminal-with-presentation \
    tailscale warp-taskbar; do
    mock_bin "$stub" <<STUB
#!/bin/bash
mock_log "$stub \$*"
STUB
  done
  cp "$REPO_ROOT/bin/ohmydebn-require-systemd" "$MOCK_BIN/"
  for script in ohmydebn-tailscale ohmydebn-tailscale-install ohmydebn-cloudflare-warp ohmydebn-cloudflare-warp-install; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#^SYSTEMD_DIR=.*#SYSTEMD_DIR=$SYSTEMD_DIR#; s#/usr/bin/tailscale systray#$MOCK_BIN/tailscale systray#; s#/bin/warp-taskbar#$MOCK_BIN/warp-taskbar#" \
      "$REPO_ROOT/bin/$script" >"$MOCK_DIR/$script"
  done
}
# run <stdin> <script> [args]
run() {
  local input="$1"
  shift
  OUT=$(printf '%s' "$input" | OHMYDEBN_TEST_SYSTEMD_DIR="$SYSTEMD_DIR" MOCK_INSTALLED="${MOCK_INSTALLED:-}" \
    PATH="$(mock_path)" bash "$@" 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

# --- the helper ---
setup
run "" "$MOCK_BIN/ohmydebn-require-systemd" Tailscale tailscale "$MOCK_BIN/ohmydebn-tailscale-remove"
assert_eq "systemd: exits 0" "0" "$STATUS"
assert_eq "systemd: says nothing" "" "$OUT"
mock_cleanup

MOCK_SYSTEMD=false setup
run "" "$MOCK_BIN/ohmydebn-require-systemd" Tailscale tailscale "$MOCK_BIN/ohmydebn-tailscale-remove"
assert_eq "no systemd: exits 1" "1" "$STATUS"
assert_contains "no systemd: says why" "$OUT" "Tailscale can't run on this system. Its background service is started only by"
assert_contains "no systemd, not installed: nothing installed" "$OUT" "Nothing was installed."
assert_not_contains "no systemd, not installed: no question" "$OUT" "[y/N]"
mock_cleanup

MOCK_SYSTEMD=false setup
MOCK_INSTALLED=tailscale run "y" "$MOCK_BIN/ohmydebn-require-systemd" Tailscale tailscale "$MOCK_BIN/ohmydebn-tailscale-remove"
assert_eq "installed, answered y: exits 1" "1" "$STATUS"
assert_contains "installed: says it can't connect" "$OUT" "Tailscale is installed, but its service isn't running"
assert_contains "installed, answered y: its remover runs, without asking again" "$CALLS" "ohmydebn-tailscale-remove --skip-prompt"
mock_cleanup

MOCK_SYSTEMD=false setup
MOCK_INSTALLED=tailscale run "" "$MOCK_BIN/ohmydebn-require-systemd" Tailscale tailscale "$MOCK_BIN/ohmydebn-tailscale-remove"
assert_contains "installed: asks, defaulting to no" "$OUT" "Remove Tailscale? [y/N]"
assert_not_contains "installed, Enter: nothing removed" "$CALLS" "ohmydebn-tailscale-remove"
mock_cleanup

MOCK_SYSTEMD=false setup
MOCK_INSTALLED=tailscale run "y" "$MOCK_BIN/ohmydebn-require-systemd" --skip-prompt Tailscale tailscale "$MOCK_BIN/ohmydebn-tailscale-remove"
assert_not_contains "--skip-prompt: no question" "$OUT" "[y/N]"
assert_not_contains "--skip-prompt: nothing removed" "$CALLS" "ohmydebn-tailscale-remove"
mock_cleanup

# --- the installers and launchers ---
for spec in "tailscale tailscale Tailscale" "cloudflare-warp cloudflare-warp Cloudflare_WARP"; do
  read -r app pkg name <<<"$spec"
  name=${name//_/ }

  MOCK_SYSTEMD=false setup
  run "" "$MOCK_DIR/ohmydebn-$app-install"
  assert_eq "$app installer, no systemd: exits 1" "1" "$STATUS"
  assert_contains "$app installer, no systemd: says why" "$OUT" "$name can't run on this system"
  assert_not_contains "$app installer, no systemd: no Press Enter" "$OUT" "Press Enter"
  assert_not_contains "$app installer, no systemd: nothing downloaded" "$CALLS" "curl"
  assert_not_contains "$app installer, no systemd: nothing run as root" "$CALLS" "sudo"
  mock_cleanup

  MOCK_SYSTEMD=false setup
  MOCK_INSTALLED=$pkg run "" "$MOCK_DIR/ohmydebn-$app-install" --skip-prompt
  assert_eq "$app installer --skip-prompt, installed, no systemd: exits 1" "1" "$STATUS"
  assert_not_contains "$app installer --skip-prompt: no question" "$OUT" "[y/N]"
  mock_cleanup

  setup
  run "" "$MOCK_DIR/ohmydebn-$app-install"
  assert_contains "$app installer, systemd: goes on to ask" "$OUT" "Press Enter to continue or Ctrl-C to cancel."
  mock_cleanup

  MOCK_SYSTEMD=false setup
  MOCK_INSTALLED=$pkg run "" "$MOCK_DIR/ohmydebn-$app"
  assert_contains "$app launcher, installed, no systemd: opens the installer's window to say why" "$CALLS" \
    "ohmydebn-launch-floating-terminal-with-presentation $name $MOCK_BIN/ohmydebn-$app-install"
  assert_not_contains "$app launcher, installed, no systemd: doesn't start the app" "$CALLS" \
    "$([ "$app" = tailscale ] && echo "tailscale systray" || echo warp-taskbar)"
  mock_cleanup

  setup
  MOCK_INSTALLED=$pkg run "" "$MOCK_DIR/ohmydebn-$app"
  assert_contains "$app launcher, installed, systemd: starts the app" "$CALLS" \
    "$([ "$app" = tailscale ] && echo "tailscale systray" || echo warp-taskbar)"
  assert_not_contains "$app launcher, installed, systemd: no installer window" "$CALLS" "with-presentation"
  mock_cleanup
done

test_summary
