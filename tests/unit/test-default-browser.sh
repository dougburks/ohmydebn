#!/bin/bash
#
# Unit tests for the Brave Origin default-browser switch:
# install/packaging/browser.sh (installs it on new installs only, falling
# back to Chromium), install/config/mimetypes.sh (makes whichever browser is
# present the default - Brave Origin first - on new installs only), and
# bin/ohmydebn-chromium-install (the optional Chromium path, Ubuntu's snap
# package name included). Existing installs are the important negative
# case throughout: they keep Chromium and nothing here touches them.
#
# The scripts' hardcoded /usr/share/ohmydebn paths are sed-patched to the
# mock bin dir; dpkg answers from MOCK_INSTALLED, snap from MOCK_SNAPS, and
# HOME is a scratch dir so the install-complete marker can be present or
# absent per scenario.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/packaging/browser.sh / install/config/mimetypes.sh / ohmydebn-chromium-install ==="

setup() {
  mock_init
  H="$MOCK_DIR/home"
  mkdir -p "$H"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  mock_bin snap <<'EOF2'
#!/bin/bash
[[ "$1" == "list" && " ${MOCK_SNAPS:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  for name in sudo xdg-settings xdg-mime ohmydebn-headline ohmydebn-brave-repo; do
    mock_bin "$name" <<EOF2
#!/bin/bash
echo "$name \$*" >>"\$MOCK_CALLS"
exit 0
EOF2
  done
  # ohmydebn-brave-origin-install succeeds unless MOCK_BRAVE_FAILS is set;
  # ohmydebn-chromium-install is mocked here (the real one is tested below).
  mock_bin ohmydebn-brave-origin-install <<'EOF2'
#!/bin/bash
echo "ohmydebn-brave-origin-install $*" >>"$MOCK_CALLS"
[[ -n "${MOCK_BRAVE_FAILS:-}" ]] && exit 1
exit 0
EOF2
  mock_bin ohmydebn-chromium-install <<'EOF2'
#!/bin/bash
echo "ohmydebn-chromium-install $*" >>"$MOCK_CALLS"
exit 0
EOF2
  for script in install/packaging/browser.sh install/config/mimetypes.sh; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/$script" >"$MOCK_DIR/$(basename "$script")"
  done
}
run() {
  HOME="$H" PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" MOCK_SNAPS="${MOCK_SNAPS:-}" \
    MOCK_BRAVE_FAILS="${MOCK_BRAVE_FAILS:-}" bash "$@" </dev/null >/dev/null 2>&1
}

# --- browser.sh: new install -> Brave Origin installed, no fallback ---
setup
run "$MOCK_DIR/browser.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "new install: Brave Origin installed without prompting" "$CALLS" "ohmydebn-brave-origin-install --skip-prompt"
assert_not_contains "new install: no Chromium fallback when Brave Origin succeeds" "$CALLS" "ohmydebn-chromium-install"
mock_cleanup

# --- browser.sh: existing install -> untouched (keeps Chromium) ---
setup
mkdir -p "$H/.local/state"
touch "$H/.local/state/ohmydebn"
run "$MOCK_DIR/browser.sh"
assert_eq "existing install: nothing installed" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- browser.sh: Brave Origin install fails -> its repo (ours) removed, Chromium installed ---
setup
mock_bin ohmydebn-brave-repo <<'EOF2'
#!/bin/bash
echo "ohmydebn-brave-repo $*" >>"$MOCK_CALLS"
exit 0
EOF2
MOCK_BRAVE_FAILS=1 run "$MOCK_DIR/browser.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "brave fails: repo we added is removed again" "$CALLS" "ohmydebn-brave-repo remove"
assert_contains "brave fails: Chromium installed as the fallback" "$CALLS" "ohmydebn-chromium-install --skip-prompt"
mock_cleanup

# --- browser.sh: Brave Origin install fails on a distro whose repo it isn't ours -> repo left alone ---
setup
mock_bin ohmydebn-brave-repo <<'EOF2'
#!/bin/bash
echo "ohmydebn-brave-repo $*" >>"$MOCK_CALLS"
[[ "$1" == is-ours ]] && exit 1
exit 0
EOF2
MOCK_BRAVE_FAILS=1 run "$MOCK_DIR/browser.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "brave fails, distro repo: not removed" "$CALLS" "ohmydebn-brave-repo remove"
assert_contains "brave fails, distro repo: Chromium still the fallback" "$CALLS" "ohmydebn-chromium-install --skip-prompt"
mock_cleanup

# --- mimetypes.sh: new install with Brave Origin -> it becomes the default browser and PDF viewer ---
setup
MOCK_INSTALLED="brave-origin chromium" run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "new install: Brave Origin wins over an also-present Chromium (xdg default)" "$CALLS" "xdg-settings set default-web-browser brave-origin.desktop"
assert_contains "new install: http handler" "$CALLS" "xdg-mime default brave-origin.desktop x-scheme-handler/http"
assert_contains "new install: https handler" "$CALLS" "xdg-mime default brave-origin.desktop x-scheme-handler/https"
assert_contains "new install: x-www-browser selects the path Brave's package registered" "$CALLS" "sudo update-alternatives --set x-www-browser /usr/bin/brave-origin-stable"
assert_contains "new install: gnome-www-browser too" "$CALLS" "sudo update-alternatives --set gnome-www-browser /usr/bin/brave-origin-stable"
assert_contains "new install: PDF viewer" "$CALLS" "xdg-mime default brave-origin.desktop application/pdf"
assert_contains "new install: headline names the browser" "$CALLS" "ohmydebn-headline Configuring Brave Origin as default web browser"
assert_not_contains "new install: chromium not configured" "$CALLS" "chromium.desktop"
assert_eq "new install: PDF marker written" "yes" "$([ -f "$H/.local/state/ohmydebn-config/pdf-20251107" ] && echo yes || echo no)"
mock_cleanup

# --- mimetypes.sh: new install where only Chromium is present (fallback) -> Chromium as before ---
setup
MOCK_INSTALLED="chromium" run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "chromium only: xdg default" "$CALLS" "xdg-settings set default-web-browser chromium.desktop"
assert_contains "chromium only: alternative" "$CALLS" "sudo update-alternatives --set x-www-browser /usr/bin/chromium"
assert_contains "chromium only: PDF viewer" "$CALLS" "xdg-mime default chromium.desktop application/pdf"
mock_cleanup

# --- mimetypes.sh: new install, Ubuntu snap chromium only -> snap desktop id and binary ---
setup
MOCK_SNAPS="chromium" run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "snap chromium: xdg default" "$CALLS" "xdg-settings set default-web-browser chromium_chromium.desktop"
assert_contains "snap chromium: alternative" "$CALLS" "sudo update-alternatives --set x-www-browser /snap/bin/chromium"
mock_cleanup

# --- mimetypes.sh: no browser at all -> only the image viewer step ---
setup
run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "no browser: no default-browser step" "$CALLS" "default-web-browser"
assert_not_contains "no browser: no PDF step" "$CALLS" "application/pdf"
assert_contains "no browser: ristretto still configured" "$CALLS" "org.xfce.ristretto.desktop"
mock_cleanup

# --- mimetypes.sh: existing install (marker + PDF marker) with Brave Origin newly present -> untouched ---
setup
mkdir -p "$H/.local/state/ohmydebn-config"
touch "$H/.local/state/ohmydebn" "$H/.local/state/ohmydebn-config/pdf-20251107"
MOCK_INSTALLED="brave-origin chromium" run "$MOCK_DIR/mimetypes.sh"
assert_eq "existing install: default browser and PDF viewer left alone" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- mimetypes.sh: existing install without the PDF marker -> PDF only, browser default untouched ---
setup
mkdir -p "$H/.local/state"
touch "$H/.local/state/ohmydebn"
MOCK_INSTALLED="chromium" run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "existing install, no PDF marker: default browser untouched" "$CALLS" "default-web-browser"
assert_contains "existing install, no PDF marker: PDF step still runs" "$CALLS" "xdg-mime default chromium.desktop application/pdf"
mock_cleanup

# --- ohmydebn-chromium-install: real script; apt logged, os-release and the seed source patched ---
setup_chromium() {
  setup
  ROOT="$MOCK_DIR/root"
  mkdir -p "$ROOT/usr/share/ohmydebn/config/chromium/External Extensions" "$ROOT/etc"
  echo '{}' >"$ROOT/usr/share/ohmydebn/config/chromium/External Extensions/x.json"
  echo "ID=$1" >"$ROOT/etc/os-release"
  sed "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g; s#/etc/os-release#$ROOT/etc/os-release#g" \
    "$REPO_ROOT/install/config/chromium.sh" >"$ROOT/chromium.sh"
  mkdir -p "$ROOT/usr/share/ohmydebn/install/config" "$ROOT/usr/share/ohmydebn/bin"
  mv "$ROOT/chromium.sh" "$ROOT/usr/share/ohmydebn/install/config/chromium.sh"
  # chromium.sh's headline call is patched to the scratch root too - it has
  # to exist there, or `set -e` in the installer ends the seed step early.
  ln -s "$MOCK_BIN/ohmydebn-headline" "$ROOT/usr/share/ohmydebn/bin/ohmydebn-headline"
  sed "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g; s#/etc/os-release#$ROOT/etc/os-release#g" \
    "$REPO_ROOT/bin/ohmydebn-chromium-install" >"$MOCK_DIR/chromium-install.sh"
}

# Debian, not installed: prompt skipped, chromium installed without recommends
setup_chromium debian
run "$MOCK_DIR/chromium-install.sh" --skip-prompt
assert_contains "debian: installs chromium" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y --no-install-recommends install chromium"
mock_cleanup

# Ubuntu, not installed: the transitional chromium-browser package instead
setup_chromium ubuntu
run "$MOCK_DIR/chromium-install.sh" --skip-prompt
assert_contains "ubuntu: installs chromium-browser" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y --no-install-recommends install chromium-browser"
mock_cleanup

# Debian, already installed, no profile yet: no apt, uBlock seed applied
setup_chromium debian
MOCK_INSTALLED="chromium" run "$MOCK_DIR/chromium-install.sh" --skip-prompt
assert_not_contains "installed: no apt call" "$(cat "$MOCK_CALLS")" "apt"
assert_eq "installed: uBlock Origin Lite seeded into a fresh profile" "yes" "$([ -f "$H/.config/chromium/External Extensions/x.json" ] && echo yes || echo no)"
mock_cleanup

# Debian, installed with an existing profile: never overwritten
setup_chromium debian
mkdir -p "$H/.config/chromium"
MOCK_INSTALLED="chromium" run "$MOCK_DIR/chromium-install.sh" --skip-prompt
assert_eq "existing profile: left alone" "no" "$([ -e "$H/.config/chromium/External Extensions" ] && echo yes || echo no)"
mock_cleanup

# Without --skip-prompt and stdin closed: the prompt's read fails, nothing installed
setup_chromium debian
run "$MOCK_DIR/chromium-install.sh"
EXIT_CODE=$?
assert_eq "cancelled at the prompt: exits non-zero" "1" "$EXIT_CODE"
assert_not_contains "cancelled at the prompt: nothing installed" "$(cat "$MOCK_CALLS")" "apt"
mock_cleanup

test_summary
