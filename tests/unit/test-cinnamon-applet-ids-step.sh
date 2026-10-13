#!/bin/bash
#
# Unit tests for install/config/cinnamon-applet-ids.sh: it runs
# ohmydebn-cinnamon-applet-ids (with a headline) only when the dry run
# reports duplicate applet IDs, asks for the Cinnamon restart that clears
# the running panel's stale copy of a renumbered applet, and never fails
# the install. The script itself is mocked; its planning is tested in
# test-cinnamon-applet-ids.py.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STEP="$REPO_ROOT/install/config/cinnamon-applet-ids.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/cinnamon-applet-ids.sh ==="

# setup <what the dry run prints> <exit code of the real run>
setup() {
  mock_init
  printf '%s' "$1" >"$MOCK_DIR/dry-run-output"
  echo "$2" >"$MOCK_DIR/run-exit"
  mock_bin ohmydebn-cinnamon-applet-ids <<'STUB'
#!/bin/bash
if [ "${1:-}" = "--dry-run" ]; then
  mock_log "dry-run"
  cat "$MOCK_DIR/dry-run-output"
else
  mock_log "fix"
  exit "$(cat "$MOCK_DIR/run-exit")"
fi
STUB
  mock_bin ohmydebn-headline <<'STUB'
#!/bin/bash
mock_log "headline $*"
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$STEP" >"$MOCK_DIR/step.sh"
}

# Sourced, as ohmydebn.sh sources it, so the restart request it leaves
# behind can be read.
run_step() {
  RESTART=$(env -u OHMYDEBN_CINNAMON_RESTART_NEEDED PATH="$(mock_path)" bash -ec \
    'source "$1" >/dev/null 2>&1; echo "${OHMYDEBN_CINNAMON_RESTART_NEEDED:-}"' _ "$MOCK_DIR/step.sh" </dev/null)
  STATUS=$?
}

setup "Panel applet network@cinnamon.org: ID 10 -> 17" 0
run_step
assert_eq "duplicates: install continues" "0" "$STATUS"
assert_eq "duplicates: announced, then fixed" "dry-run
headline Giving each panel applet its own ID
fix" "$(cat "$MOCK_CALLS")"
assert_eq "duplicates: Cinnamon restart requested (the panel shows the old copy until then)" "1" "$RESTART"
mock_cleanup

setup "" 0
run_step
assert_eq "unique IDs already: only the dry run, nothing announced or changed" "dry-run" "$(cat "$MOCK_CALLS")"
assert_eq "unique IDs already: no restart requested" "" "$RESTART"
mock_cleanup

setup "Panel applet network@cinnamon.org: ID 10 -> 17" 1
run_step
assert_eq "the fix failing never fails the install" "0" "$STATUS"
assert_eq "the fix failing: no restart requested" "" "$RESTART"
mock_cleanup

test_summary
