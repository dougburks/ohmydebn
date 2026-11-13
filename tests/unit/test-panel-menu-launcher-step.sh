#!/bin/bash
#
# Unit tests for install/config/panel-menu-launcher.sh: it adds the
# OhMyDebn Menu to the panel once, then the AI Assistant beside it once
# (--add-ai, for installs from before it existed), and sets each step's
# marker only when ohmydebn-panel-menu-launcher could read the panel, so a
# run without a desktop session tries again on the next update.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/panel-menu-launcher.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/panel-menu-launcher.sh ==="

MARKER_NAME=panel-menu-launcher-20261016
AI_MARKER_NAME=panel-ai-launcher-20261113

run_step() { # exit status of the mocked ohmydebn-panel-menu-launcher
  mock_bin ohmydebn-panel-menu-launcher <<MOCK
#!/bin/bash
mock_log "panel-menu-launcher \$*"
exit $1
MOCK
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/step.sh"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/step.sh" </dev/null >/dev/null 2>&1
}
marker() {
  [ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/${1:-$MARKER_NAME}" ] && echo yes || echo no
}
calls() { tr '\n' '|' <"$MOCK_CALLS" | sed 's/ |/|/g; s/|$//'; }

# Scenario 1: first run, panel read - both steps run, both markers set.
mock_init
SCRATCH_HOME=$(mktemp -d)
run_step 0
assert_eq "first run: the launcher, then the AI button" "panel-menu-launcher|panel-menu-launcher --add-ai" "$(calls)"
assert_eq "first run: marker set" "yes" "$(marker)"
assert_eq "first run: AI marker set" "yes" "$(marker "$AI_MARKER_NAME")"

# Scenario 2: later runs - not run again, so a removed button stays removed.
: >"$MOCK_CALLS"
run_step 0
assert_eq "markers present: not run again" "" "$(calls)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: the panel couldn't be read - no markers, so the next run tries again.
mock_init
SCRATCH_HOME=$(mktemp -d)
run_step 1
assert_eq "no desktop session: no marker" "no" "$(marker)"
assert_eq "no desktop session: no AI marker" "no" "$(marker "$AI_MARKER_NAME")"
run_step 0
assert_eq "next run: tried again and marked" "yes" "$(marker)"
assert_eq "next run: AI marked too" "yes" "$(marker "$AI_MARKER_NAME")"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 4: an install from before the AI button (4.12.0 to 4.17.0) -
# only the AI step runs, once.
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$MARKER_NAME"
run_step 0
assert_eq "existing install: only the AI button is added" "panel-menu-launcher --add-ai" "$(calls)"
assert_eq "existing install: AI marker set" "yes" "$(marker "$AI_MARKER_NAME")"
: >"$MOCK_CALLS"
run_step 0
assert_eq "existing install: not again" "" "$(calls)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
