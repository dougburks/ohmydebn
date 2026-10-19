#!/bin/bash
#
# Unit tests for install/config/panel-menu-launcher.sh: it adds the
# OhMyDebn Menu to the panel once, and sets its marker only when
# ohmydebn-panel-menu-launcher could read the panel, so a run without a
# desktop session tries again on the next update.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/panel-menu-launcher.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/panel-menu-launcher.sh ==="

MARKER_NAME=panel-menu-launcher-20261016

run_step() { # exit status of the mocked ohmydebn-panel-menu-launcher
  mock_bin ohmydebn-panel-menu-launcher <<MOCK
#!/bin/bash
mock_log "panel-menu-launcher"
exit $1
MOCK
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/step.sh"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/step.sh" </dev/null >/dev/null 2>&1
}
marker() {
  [ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/$MARKER_NAME" ] && echo yes || echo no
}

# Scenario 1: first run, panel read - launcher step runs, marker set.
mock_init
SCRATCH_HOME=$(mktemp -d)
run_step 0
assert_eq "first run: launcher step runs" "panel-menu-launcher" "$(cat "$MOCK_CALLS")"
assert_eq "first run: marker set" "yes" "$(marker)"

# Scenario 2: later runs - not run again, so a removed button stays removed.
: >"$MOCK_CALLS"
run_step 0
assert_eq "marker present: not run again" "" "$(cat "$MOCK_CALLS")"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: the panel couldn't be read - no marker, so the next run tries again.
mock_init
SCRATCH_HOME=$(mktemp -d)
run_step 1
assert_eq "no desktop session: no marker" "no" "$(marker)"
run_step 0
assert_eq "next run: tried again and marked" "yes" "$(marker)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
