#!/bin/bash
#
# Unit tests for install/finalization/finale.sh's consolidated Cinnamon
# restart. finalization/gtile-restart-flag.sh and install/keybinding/keybinding.sh
# each set OHMYDEBN_CINNAMON_RESTART_NEEDED instead of restarting Cinnamon
# directly, so two independent backgrounded `cinnamon --replace &` calls
# in the same run can't race each other - finale.sh (the last finalization
# step) does the one actual restart here if anything asked for it, and
# only if there's actually a live Cinnamon session to restart
# (pgrep -x cinnamon), checked fresh here rather than trusting whatever
# was true when the flag was set.
#
# setsid/cinnamon are mocked (and the script patched to point at the mock)
# so this test can never risk touching a real, live Cinnamon session.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/finalization/finale.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/finalization/finale.sh (consolidated restart) ==="

setup_mocks() {
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF
  mock_bin ohmydebn-version <<'EOF'
#!/bin/bash
echo "9.9.9-99999999"
EOF
  mock_bin cinnamon <<'EOF'
#!/bin/bash
mock_log "cinnamon $*"
exit 0
EOF
  mock_bin pgrep <<'EOF'
#!/bin/bash
mock_log "pgrep $*"
if [[ "${MOCK_CINNAMON_RUNNING:-true}" == "true" ]]; then
  echo "12345"
  exit 0
fi
exit 1
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/bin/cinnamon#$MOCK_BIN/cinnamon#g" "$SCRIPT" >"$MOCK_DIR/finale-patched.sh"
}

run_script() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" XDG_CURRENT_DESKTOP="X-Cinnamon" \
    OHMYDEBN_CINNAMON_RESTART_NEEDED="${RESTART_NEEDED:-}" \
    bash -e "$MOCK_DIR/finale-patched.sh" >/dev/null 2>&1
}

# setsid ... & backgrounds the restart - poll briefly for the mock to have
# actually run and logged its call, rather than racing it.
wait_for_cinnamon_call() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -q "cinnamon --replace" "$MOCK_CALLS" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# Scenario 1: flag set, Cinnamon running -> restarts.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state" && touch "$SCRATCH_HOME/.local/state/ohmydebn"  # "update complete" path, not first-install
RESTART_NEEDED=1 MOCK_CINNAMON_RUNNING=true run_script
wait_for_cinnamon_call
CALLS=$(cat "$MOCK_CALLS")
assert_contains "flag set, Cinnamon running: restarted" "$CALLS" "cinnamon --replace"
assert_contains "flag set, Cinnamon running: headline shown" "$CALLS" "Restarting Cinnamon to apply changes"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: flag set, but no live Cinnamon session -> no restart
# (nothing to restart, and don't accidentally launch a fresh one).
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state" && touch "$SCRATCH_HOME/.local/state/ohmydebn"
RESTART_NEEDED=1 MOCK_CINNAMON_RUNNING=false run_script
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "flag set, Cinnamon not running: no restart" "$CALLS" "cinnamon --replace"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: no flag set, Cinnamon running -> no restart (nothing asked
# for one).
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state" && touch "$SCRATCH_HOME/.local/state/ohmydebn"
RESTART_NEEDED="" MOCK_CINNAMON_RUNNING=true run_script
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "no flag: no restart" "$CALLS" "cinnamon --replace"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
