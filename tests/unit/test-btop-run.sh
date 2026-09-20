#!/bin/bash
#
# Unit tests for bin/ohmydebn-btop-run, the loop that keeps the Super+T
# btop window alive across a theme change on a btop too old to hot-reload
# (< 1.3.1, e.g. Ubuntu 24.04 / Linux Mint 22's 1.3.0): SIGUSR2 has no
# handler there and terminates btop, and the loop must run it again in the
# same terminal window - and ONLY then. Any other way btop ends (`q`,
# Ctrl+C, a crash, the window closing) must end the loop with btop's own
# exit status, so the window closes as it always has. The SIGUSR2 case is
# exercised with a real signal death (the stub kills itself with USR2)
# rather than a faked exit code, so the 128+signal arithmetic the loop
# relies on is actually tested.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-btop-run"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-btop-run ==="

# Installs a btop stub whose body is the given script text, patches the
# loop to call it, runs the loop with the given args, and leaves the loop's
# exit status in RUN_STATUS. Every stub logs its invocation (with args) so
# the tests can count how many times btop was run.
run_loop_with_btop_stub() {
  local body="$1"
  shift
  mock_bin btop <<EOF
#!/bin/bash
mock_log "btop \$*"
$body
EOF
  sed -e "s#/usr/bin/btop#$MOCK_BIN/btop#g" "$SCRIPT" >"$MOCK_DIR/btop-run-patched.sh"
  PATH="$(mock_path)" bash "$MOCK_DIR/btop-run-patched.sh" "$@" >/dev/null 2>&1
  RUN_STATUS=$?
}

# Killed by SIGUSR2 once (old btop hit by the theme-set signal), then a
# normal quit: btop must be run twice, and the loop must exit cleanly.
mock_init
run_loop_with_btop_stub '
if [ ! -f "$MOCK_DIR/already-died" ]; then
  touch "$MOCK_DIR/already-died"
  kill -USR2 $$
fi
exit 0
'
assert_eq "SIGUSR2 death: btop restarted in place (run twice)" "2" "$(grep -c '^btop' "$MOCK_CALLS")"
assert_eq "SIGUSR2 death then quit: loop exits 0" "0" "$RUN_STATUS"
mock_cleanup

# Normal quit (`q`, Escape, Ctrl+C all exit 0): run once, exit 0.
mock_init
run_loop_with_btop_stub 'exit 0'
assert_eq "normal quit: btop run once" "1" "$(grep -c '^btop' "$MOCK_CALLS")"
assert_eq "normal quit: loop exits 0" "0" "$RUN_STATUS"
mock_cleanup

# Non-zero exit (a crash or startup failure): run once, status passed
# through so the window closes rather than a broken btop being relaunched
# forever.
mock_init
run_loop_with_btop_stub 'exit 3'
assert_eq "exit 3: btop run once" "1" "$(grep -c '^btop' "$MOCK_CALLS")"
assert_eq "exit 3: loop passes status through" "3" "$RUN_STATUS"
mock_cleanup

# Death by a different signal (SIGTERM, as when the window is closed): not
# a theme change, so no restart - only SIGUSR2 means "restart me".
mock_init
run_loop_with_btop_stub 'kill -TERM $$'
assert_eq "SIGTERM death: btop run once, not restarted" "1" "$(grep -c '^btop' "$MOCK_CALLS")"
assert_eq "SIGTERM death: 128+15 passed through" "143" "$RUN_STATUS"
mock_cleanup

# Arguments reach btop unchanged.
mock_init
run_loop_with_btop_stub 'exit 0' --utf-force -p 1
assert_contains "args passed through to btop" "$(cat "$MOCK_CALLS")" "btop --utf-force -p 1"
mock_cleanup

test_summary
