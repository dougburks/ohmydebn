#!/bin/bash
#
# Unit tests for --skip-prompt across the installers that used to ignore
# it: each always printed "Press Enter to continue or Ctrl-C to cancel."
# and waited on read -r, and the AI/browser ones then asked "make it the
# default? [y/N]" too. Under --skip-prompt ("part of an install or
# automation: ask nothing") none of that may appear, and the install must
# still run with nothing on stdin; without it, the prompt is still there.
#
# Each script's /usr/share/ohmydebn/bin paths are sed-patched to the mock
# bin dir. dpkg reports nothing installed, so the install path runs; sudo,
# curl, uname and the OhMyDebn helpers are stand-ins (the set-default ones
# print "[y/N]", so a question that isn't gated shows up in the output).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== installers: --skip-prompt ==="

# The directory the installers are read from; tests/unit can point it at
# other copies (such as the ones in git HEAD) to check this test itself.
SRC_DIR="${OHMYDEBN_TEST_SRC_DIR:-$REPO_ROOT/bin}"

SCRIPTS="chatgpt cliamp cloudflare-warp code distrobox docker firefox-esr gestures
  google-chrome-stable helium-bin localsend powershell simplescreenrecorder tailscale velo"

# setup <script name>
setup() {
  mock_init
  mkdir -p "$MOCK_DIR/home/.config/net.imput.helium"
  printf 'ID=debian\nVERSION_CODENAME=trixie\n' >"$MOCK_DIR/os-release"
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 1
STUB
  # Reads what's piped into `sudo tee`, so the writer never hits a closed
  # pipe under pipefail.
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
case "$*" in *tee*) cat >/dev/null ;; esac
exit 0
STUB
  # Docker asks whether the distro has docker-cli; read-only, but not the
  # host's apt to ask.
  mock_bin apt-cache <<'STUB'
#!/bin/bash
exit 100
STUB
  mock_bin uname <<'STUB'
#!/bin/bash
echo x86_64
STUB
  # A key download writes a file to -o; VS Code's update API answers JSON.
  mock_bin curl <<'STUB'
#!/bin/bash
mock_log "curl $*"
while [ $# -gt 0 ]; do
  if [ "$1" = -o ]; then
    echo key >"$2"
    exit 0
  fi
  shift
done
echo '{"url": "https://example.invalid/code.deb", "sha256hash": "abc"}'
STUB
  # Answers whichever fingerprint the script under test expects.
  mock_bin ohmydebn-pgp-fingerprint <<STUB
#!/bin/bash
echo $(grep -oE '\b[0-9A-F]{40}\b' "$SRC_DIR/ohmydebn-$1-install" | head -1)
STUB
  for name in ohmydebn-apt-install-deb ohmydebn-powershell-repo; do
    mock_bin "$name" <<STUB
#!/bin/bash
mock_log "$name \$*"
STUB
  done
  for name in ohmydebn-ai-set-default ohmydebn-browser-set-default; do
    mock_bin "$name" <<STUB
#!/bin/bash
mock_log "$name \$*"
echo "Make it the default? [y/N]"
STUB
  done
  stub_install_checks
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SRC_DIR/ohmydebn-$1-install" >"$MOCK_DIR/install"
}

# run <stdin text> [args]
run() {
  local input="$1"
  shift
  OUTPUT=$(printf '%s' "$input" | HOME="$MOCK_DIR/home" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" \
    PATH="$(mock_path)" bash "$MOCK_DIR/install" "$@" 2>&1)
  STATUS=$?
}

for script in $SCRIPTS; do
  setup "$script"
  run "" --skip-prompt </dev/null
  assert_eq "$script --skip-prompt: exits 0 with nothing on stdin" "0" "$STATUS"
  assert_not_contains "$script --skip-prompt: no Press Enter" "$OUTPUT" "Press Enter"
  assert_not_contains "$script --skip-prompt: no [y/N] question" "$OUTPUT" "[y/N]"
  # VS Code installs through ohmydebn-apt-install-deb; the rest through apt.
  assert_contains "$script --skip-prompt: still installs" "$(cat "$MOCK_CALLS")" \
    "$([ "$script" = code ] && echo ohmydebn-apt-install-deb || echo "sudo /usr/bin/apt -y install")"
  mock_cleanup

  setup "$script"
  run $'\n'
  assert_eq "$script without --skip-prompt: exits 0" "0" "$STATUS"
  assert_contains "$script without --skip-prompt: asks Press Enter" "$OUTPUT" "Press Enter"
  mock_cleanup
done

test_summary
