#!/bin/bash
#
# Unit tests for install/keybinding/keybinding.sh's restart-flag
# behavior. Like finalization/gtile-restart-flag.sh, this no longer restarts
# Cinnamon directly - it sets the same shared OHMYDEBN_CINNAMON_RESTART_NEEDED
# variable, so the two don't race each other with independent backgrounded
# `cinnamon --replace &` calls in the same run. finalization/finale.sh
# does the one actual restart at the end (see test-finale-restart.sh).
#
# This test only covers the restart-flag branch, not the keybinding
# content itself (which gsettings key gets which value) - gsettings is
# mocked to a no-op that accepts anything, since that part is unchanged
# by this refactor.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/keybinding/keybinding.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

# Read straight from the script rather than hardcoding the date-stamped
# marker name here too - keybinding.sh's KEYBINDING_STATE gets bumped every
# time a hotkey changes, and a second hardcoded copy here would silently
# fall out of sync (as happened when the marker was bumped to add the
# herdr/tmux hotkeys but this test's copy wasn't updated to match).
KEYBINDING_MARKER=$(grep -oP '(?<=KEYBINDING_STATE=\$STATE_DIR/)\S+' "$SCRIPT")

echo "=== install/keybinding/keybinding.sh (restart flag) ==="

setup_mocks() {
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF
  mock_bin gsettings <<'EOF'
#!/bin/bash
mock_log "gsettings $*"
exit 0
EOF
  # pgrep -x cinnamon is how the real script checks for a live session to
  # restart - mocked so the test controls it instead of depending on
  # whatever's actually running on the machine the tests execute on.
  mock_bin pgrep <<'EOF'
#!/bin/bash
mock_log "pgrep $*"
if [[ "${MOCK_CINNAMON_RUNNING:-true}" == "true" ]]; then
  echo "12345"
  exit 0
fi
exit 1
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn/install/keybinding#$REPO_ROOT/install/keybinding#g" "$SCRIPT" >"$MOCK_DIR/keybinding-patched.sh"
}

# Sources (doesn't exec) the patched script - required to observe
# OHMYDEBN_CINNAMON_RESTART_NEEDED, which only propagates back to the
# caller via `source`, matching how finalization/hotkeys.sh invokes it
# for real. Sets RESTART_FLAG to "1" or "".
# OHMYDEBN_CINNAMON_RESTART_NEEDED= clears whatever this var already is in
# the ambient environment before the child bash starts - on a real OhMyDebn
# desktop session it's commonly already exported to 1, and since the script
# under test only ever sets it (never unsets it), an inherited 1 would leak
# straight through and look like a false-positive restart flag on every
# scenario that expects none.
run_script() {
  RESTART_FLAG=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" OHMYDEBN_CINNAMON_RESTART_NEEDED= bash -c "
    source '$MOCK_DIR/keybinding-patched.sh' >/dev/null 2>&1
    echo \"\${OHMYDEBN_CINNAMON_RESTART_NEEDED:-}\"
  ")
}

# Scenario 1: first run (no state marker), Cinnamon is running -> flags a
# restart, shows the "will restart" headline, writes the state marker.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
MOCK_CINNAMON_RUNNING=true run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "first run, Cinnamon running: restart flagged" "1" "$RESTART_FLAG"
assert_contains "first run: restart headline shown" "$CALLS" "Cinnamon will restart at the end of this update to apply hotkeys"
assert_eq "first run: keybinding state marker written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: first run, Cinnamon is NOT running -> no restart flag (same
# guard the original immediate-restart code already had), but the
# keybindings themselves are still applied and the state marker still
# written.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
MOCK_CINNAMON_RUNNING=false run_script
assert_eq "first run, Cinnamon not running: no restart flag" "" "$RESTART_FLAG"
assert_eq "first run, Cinnamon not running: keybinding state marker still written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: already run (state marker pre-seeded) -> nothing happens,
# no restart flag.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER"
MOCK_CINNAMON_RUNNING=true run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "already run: no restart flag" "" "$RESTART_FLAG"
assert_not_contains "already run: no headline shown" "$CALLS" "ohmydebn-headline"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
