#!/bin/bash
#
# Unit tests for bin/ohmydebn-update-check-install's systemd guard. Devuan
# (no systemd) used to fail here: the script unconditionally wrote user
# units and called `systemctl --user`, which under set -e aborted the whole
# finalization stage of the install. It now detects a non-systemd init and
# skips the timer cleanly. Both paths are exercised with a scratch HOME and
# a mocked systemctl so nothing here touches the real system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-update-check-install"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-update-check-install: systemd guard ==="

setup_mocks() {
  mock_bin systemctl <<'EOF2'
#!/bin/bash
mock_log "systemctl $*"
# `is-enabled` is the only call whose exit code the script branches on;
# report "not enabled" so the enable path runs and gets logged too.
[[ "$2" == "is-enabled" ]] && exit 1
exit 0
EOF2
}

# Scenario 1: no systemd (Devuan) - skip cleanly, write nothing, call nothing
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
OUTPUT=$(HOME="$SCRATCH_HOME" OHMYDEBN_TEST_SYSTEMD_DIR="$MOCK_DIR/no-such-dir" \
  PATH="$(mock_path)" bash "$SCRIPT" 2>&1)
EXIT_CODE=$?
assert_eq "no systemd: exits 0 so finalization continues" "0" "$EXIT_CODE"
assert_contains "no systemd: explains the skip" "$OUTPUT" "skipping update notification timer"
assert_eq "no systemd: no user units written" "" "$(ls -A "$SCRATCH_HOME/.config/systemd/user" 2>/dev/null)"
assert_eq "no systemd: systemctl never called" "" "$(cat "$MOCK_CALLS")"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: systemd present - timer installed as before
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$MOCK_DIR/systemd-dir"
OUTPUT=$(HOME="$SCRATCH_HOME" OHMYDEBN_TEST_SYSTEMD_DIR="$MOCK_DIR/systemd-dir" \
  PATH="$(mock_path)" bash "$SCRIPT" 2>&1)
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "systemd: exits 0" "0" "$EXIT_CODE"
assert_not_contains "systemd: no skip message" "$OUTPUT" "skipping update notification timer"
assert_eq "systemd: service unit written" "yes" \
  "$([[ -f "$SCRATCH_HOME/.config/systemd/user/ohmydebn-update-check.service" ]] && echo yes)"
assert_eq "systemd: timer unit written" "yes" \
  "$([[ -f "$SCRATCH_HOME/.config/systemd/user/ohmydebn-update-check.timer" ]] && echo yes)"
assert_contains "systemd: daemon-reload called" "$CALLS" "systemctl --user daemon-reload"
assert_contains "systemd: timer enabled" "$CALLS" "systemctl --user enable ohmydebn-update-check.timer"
assert_contains "systemd: timer restarted" "$CALLS" "systemctl --user restart ohmydebn-update-check.timer"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
