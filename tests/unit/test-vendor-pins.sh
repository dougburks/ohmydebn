#!/bin/bash
#
# Unit tests for install/packaging/vendor-pins.sh: existing installs that
# got ChatGPT before 4.11.0 have OpenAI's repo (added by ChatGPT's own
# package) with no pin, so the key was trusted for any package name. The
# step adds the pin then, matching ohmydebn-chatgpt-install's exactly,
# and does nothing otherwise. It also drops pins whose repo is gone
# (ohmydebn-apt-pins --prune). sudo really runs the command it's given
# (mkdir/tee/rm in a scratch apt dir), and ohmydebn-headline is a logger.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STEP="$REPO_ROOT/install/packaging/vendor-pins.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/packaging/vendor-pins.sh ==="

setup() {
  mock_init
  APT="$MOCK_DIR/apt"
  mkdir -p "$APT/sources.list.d"
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
  # The real pin cleanup, on the scratch apt dir (OHMYDEBN_TEST_APT_DIR).
  cp "$REPO_ROOT/bin/ohmydebn-apt-pins" "$MOCK_BIN/"
}

run_step() {
  OHMYDEBN_TEST_APT_DIR="$APT" PATH="$(mock_path)" bash -e "$MOCK_DIR/step.sh" </dev/null >/dev/null 2>&1
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

# A pin left behind by an app removed with apt: cleaned up on update
setup
mkdir -p "$APT/preferences.d"
: >"$APT/preferences.d/claude-desktop.pref"
: >"$APT/preferences.d/claude-code.pref"
: >"$APT/sources.list.d/claude-code.list"
run_step
assert_eq "update: a pin whose repo is gone is removed" "no" "$([ -e "$APT/preferences.d/claude-desktop.pref" ] && echo yes || echo no)"
assert_eq "update: a pin whose repo is there stays" "yes" "$([ -e "$APT/preferences.d/claude-code.pref" ] && echo yes || echo no)"
mock_cleanup

test_summary
