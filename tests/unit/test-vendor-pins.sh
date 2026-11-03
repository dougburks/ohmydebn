#!/bin/bash
#
# Unit tests for install/packaging/vendor-pins.sh: existing installs that
# got ChatGPT before 4.11.0 have OpenAI's repo (added by ChatGPT's own
# package) with no pin, so the key was trusted for any package name. The
# step adds the pin then, matching ohmydebn-chatgpt-install's exactly,
# and does nothing otherwise. It also cleans up after apps removed with
# apt (ohmydebn-apt-pins --prune). sudo really runs the command it's given
# (mkdir/tee/rm in a scratch root), and ohmydebn-headline is a logger.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STEP="$REPO_ROOT/install/packaging/vendor-pins.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/packaging/vendor-pins.sh ==="

setup() {
  mock_init
  ROOT="$MOCK_DIR/root"
  APT="$ROOT/etc/apt"
  mkdir -p "$APT/sources.list.d" "$ROOT/usr/share/keyrings"
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
"$@"
STUB
  mock_bin ohmydebn-headline <<'STUB'
#!/bin/bash
mock_log "headline $*"
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$STEP" >"$MOCK_DIR/step.sh"
  # The real cleanup, on the scratch root (OHMYDEBN_TEST_ROOT), with
  # dpkg-query reporting MOCK_INSTALLED's packages as installed.
  cp "$REPO_ROOT/bin/ohmydebn-apt-pins" "$MOCK_BIN/"
  mock_bin dpkg-query <<'STUB'
#!/bin/bash
[[ " ${MOCK_INSTALLED:-} " == *" ${!#} "* ]] && printf installed
exit 0
STUB
}

run_step() {
  OHMYDEBN_TEST_APT_DIR="$APT" OHMYDEBN_TEST_ROOT="$ROOT" PATH="$(mock_path)" bash -e "$MOCK_DIR/step.sh" </dev/null >/dev/null 2>&1
  STATUS=$?
}

# The pin the installer writes, taken from the installer itself.
INSTALLER_PIN=$(grep -o "printf '[^']*'" "$REPO_ROOT/bin/ohmydebn-chatgpt-install" | head -1)
STEP_PIN=$(grep -o "printf '[^']*'" "$STEP" | head -1)
assert_eq "the step writes exactly the pin the installer writes" "$INSTALLER_PIN" "$STEP_PIN"

setup
: >"$APT/sources.list.d/chatgpt.sources"
run_step
assert_eq "ChatGPT repo without a pin: exits 0" "0" "$STATUS"
assert_contains "ChatGPT repo without a pin: the pin is added" "$(cat "$APT/preferences.d/chatgpt.pref" 2>/dev/null)" 'Package: chatgpt'
assert_contains "ChatGPT repo without a pin: everything else from OpenAI's origin is refused" \
  "$(cat "$APT/preferences.d/chatgpt.pref" 2>/dev/null)" 'Pin-Priority: -1'
mock_cleanup

setup
: >"$APT/sources.list.d/chatgpt.sources"
mkdir -p "$APT/preferences.d"; echo "the user's own" >"$APT/preferences.d/chatgpt.pref"
run_step
assert_eq "pin already there: left exactly as it was" "the user's own" "$(cat "$APT/preferences.d/chatgpt.pref")"
assert_eq "pin already there: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

setup
run_step
assert_eq "no ChatGPT repo: exits 0" "0" "$STATUS"
assert_eq "no ChatGPT repo: no pin, nothing run" "no" "$([ -e "$APT/preferences.d/chatgpt.pref" ] && echo yes || echo no)"
assert_eq "no ChatGPT repo: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# Brave's repo from before 4.5.0, which OhMyDebn wrote without a pin.
BRAVE_REPO_PIN=$(grep -o "printf 'Package: [^']*'[^|]*" "$REPO_ROOT/bin/ohmydebn-brave-repo" | head -1 |
  sed 's/"\$BRAVE_REPO_HOST"/"brave-browser-apt-release.s3.brave.com"/g; s/ *$//')
STEP_BRAVE_PIN=$(grep -o "printf 'Package: [^']*'[^|]*" "$STEP" | sed -n 2p | sed 's/ *$//')
assert_eq "the step writes exactly the pin ohmydebn-brave-repo writes" "$BRAVE_REPO_PIN" "$STEP_BRAVE_PIN"
assert_contains "ohmydebn-brave-repo's host is the one the step pins" \
  "$(cat "$REPO_ROOT/bin/ohmydebn-brave-repo")" 'BRAVE_REPO_HOST="brave-browser-apt-release.s3.brave.com"'

setup
: >"$APT/sources.list.d/brave-browser-release.sources"
MOCK_INSTALLED="brave-origin" run_step
PIN=$(cat "$APT/preferences.d/brave-browser-release.pref" 2>/dev/null)
assert_eq "Brave repo without a pin: exits 0" "0" "$STATUS"
assert_contains "Brave repo without a pin: Brave's packages are allowed" "$PIN" 'Package: brave-browser brave-origin brave-keyring'
assert_contains "Brave repo without a pin: everything else from Brave's origin is refused" "$PIN" 'Pin-Priority: -1'
assert_contains "Brave repo without a pin: the pin names Brave's repo" "$PIN" 'Pin: origin "brave-browser-apt-release.s3.brave.com"'
mock_cleanup

setup
: >"$APT/sources.list.d/brave-browser-release.sources"
mkdir -p "$APT/preferences.d"; echo "the user's own" >"$APT/preferences.d/brave-browser-release.pref"
MOCK_INSTALLED="brave-origin" run_step
assert_eq "Brave pin already there: left exactly as it was" "the user's own" "$(cat "$APT/preferences.d/brave-browser-release.pref")"
mock_cleanup

# A distro's own source for Brave is the distro's: Zorin OS's
# brave-browser-release.list (OhMyDebn's name, not its extension), LCOS's
# brave.list.
setup
: >"$APT/sources.list.d/brave-browser-release.list"
: >"$APT/sources.list.d/brave.list"
MOCK_INSTALLED="brave-browser" run_step
assert_eq "a distro's Brave source: no pin added" "no" "$([ -e "$APT/preferences.d/brave-browser-release.pref" ] && echo yes || echo no)"
assert_eq "a distro's Brave source: left in place" "yes yes" \
  "$([ -e "$APT/sources.list.d/brave-browser-release.list" ] && echo yes) $([ -e "$APT/sources.list.d/brave.list" ] && echo yes)"
mock_cleanup

# Leftovers of apps removed with apt: cleaned up on update
setup
mkdir -p "$APT/preferences.d"
: >"$APT/preferences.d/claude-desktop.pref"
: >"$APT/preferences.d/claude-code.pref"
: >"$APT/sources.list.d/claude-code.list"
: >"$ROOT/usr/share/keyrings/claude-code.asc"
: >"$APT/preferences.d/helium.pref"
: >"$APT/sources.list.d/helium.list"
MOCK_INSTALLED="helium-bin" run_step
assert_eq "update: a pin whose repo is gone is removed" "no" "$([ -e "$APT/preferences.d/claude-desktop.pref" ] && echo yes || echo no)"
assert_eq "update: Claude Code gone, its repo goes" "no" "$([ -e "$APT/sources.list.d/claude-code.list" ] && echo yes || echo no)"
assert_eq "update: ...and its key" "no" "$([ -e "$ROOT/usr/share/keyrings/claude-code.asc" ] && echo yes || echo no)"
assert_eq "update: an app still installed keeps its repo" "yes" "$([ -e "$APT/sources.list.d/helium.list" ] && echo yes || echo no)"
assert_eq "update: ...and its pin" "yes" "$([ -e "$APT/preferences.d/helium.pref" ] && echo yes || echo no)"
mock_cleanup

test_summary
