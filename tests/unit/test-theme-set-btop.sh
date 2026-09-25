#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-btop's version gate on the SIGUSR2
# hot-reload signal, and the in-place restart path for btop versions that
# can't hot-reload. Added after a live-VM report: btop's SIGUSR2 hot-reload
# handler was only added upstream in 1.3.1 (changelog: "Add hot-reloading
# of config file with CTRL+R or SIGUSR2 signal") - on any older btop the
# signal has no registered handler and falls back to its POSIX default
# action (terminate), which killed btop out from under its
# `alacritty -e btop` window (no --hold) the instant a theme was applied,
# on a machine running btop 1.3.0. `pkill` itself is mocked purely to
# record whether it was invoked at all - the gate must skip the broad
# call entirely below 1.3.1, not just no-op it.
#
# For the fallback branch (too old / unparseable version): the hotkey's
# own btop window runs btop under ohmydebn-btop-run, which restarts btop
# in the same window when SIGUSR2 terminates it - so the script signals
# just that window's btop (children of a running ohmydebn-btop-run) and
# nothing else. `kill` is a bash builtin (can't be mocked via PATH), so
# those scenarios spawn real short-lived background processes to stand in
# for the window's btop and for a btop the user opened by hand, and check
# which one actually got terminated, rather than mocking the kill.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-btop"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-btop ==="

# btop_version arg: what `btop --version` should print (empty string to
# simulate btop missing/unparseable output entirely).
run_with_btop_version() {
  local version="$1"
  mock_bin btop <<EOF
#!/bin/bash
echo "btop version: $version"
EOF
  mock_bin pkill <<'EOF'
#!/bin/bash
mock_log "pkill $*"
EOF
  mock_bin pgrep <<'EOF'
#!/bin/bash
mock_log "pgrep $*"
EOF
  sed -e "s#/usr/bin/btop#$MOCK_BIN/btop#g" "$SCRIPT" >"$MOCK_DIR/theme-set-btop-patched.sh"
  PATH="$(mock_path)" bash "$MOCK_DIR/theme-set-btop-patched.sh" >/dev/null 2>&1
}

mock_init
run_with_btop_version "1.3.0"
assert_not_contains "btop 1.3.0 (pre-hot-reload): broad SIGUSR2 not sent" "$(cat "$MOCK_CALLS")" "pkill"
mock_cleanup

mock_init
run_with_btop_version "1.3.1"
assert_contains "btop 1.3.1 (hot-reload added): SIGUSR2 sent to btop by exact name" "$(cat "$MOCK_CALLS")" "pkill -x -SIGUSR2 btop"
assert_not_contains "btop 1.3.1: fallback path not taken" "$(cat "$MOCK_CALLS")" "pgrep"
mock_cleanup

mock_init
run_with_btop_version "1.3.2"
assert_contains "btop 1.3.2 (newer than hot-reload): SIGUSR2 sent to btop by exact name" "$(cat "$MOCK_CALLS")" "pkill -x -SIGUSR2 btop"
mock_cleanup

mock_init
run_with_btop_version "1.2.13"
assert_not_contains "btop 1.2.13 (much older): broad SIGUSR2 not sent" "$(cat "$MOCK_CALLS")" "pkill"
mock_cleanup

mock_init
run_with_btop_version "2.0.0"
assert_contains "btop 2.0.0 (future major): SIGUSR2 sent to btop by exact name" "$(cat "$MOCK_CALLS")" "pkill -x -SIGUSR2 btop"
mock_cleanup

# btop missing/unparseable --version output: skip broad signaling rather
# than guess, same as the "too old" branches above.
mock_init
mock_bin btop <<'EOF'
#!/bin/bash
exit 127
EOF
mock_bin pkill <<'EOF'
#!/bin/bash
mock_log "pkill $*"
EOF
mock_bin pgrep <<'EOF'
#!/bin/bash
mock_log "pgrep $*"
EOF
sed -e "s#/usr/bin/btop#$MOCK_BIN/btop#g" "$SCRIPT" >"$MOCK_DIR/theme-set-btop-patched.sh"
PATH="$(mock_path)" bash "$MOCK_DIR/theme-set-btop-patched.sh" >/dev/null 2>&1
assert_not_contains "unparseable --version: broad SIGUSR2 not sent" "$(cat "$MOCK_CALLS")" "pkill"
mock_cleanup

# --- in-place restart fallback (no confirmed hot-reload support) ---

# pgrep is mocked here to stand in for the real process tree: -f returns a
# fake ohmydebn-btop-run PID, -P returns WINDOW_BTOP_PID regardless of
# which loop PID was asked about. Two real background processes play the
# roles of the window's btop (must get SIGUSR2 - `sleep` has no handler
# for it either, so it dies just like an old btop would) and of a btop the
# user opened by hand in an ordinary terminal (must be left alone), so the
# outcome is observed directly with kill -0 rather than trusting that
# `kill` was merely called with the right PID.
run_fallback_with_running_window() {
  local version="$1"
  sleep 30 &
  WINDOW_BTOP_PID=$!
  disown
  sleep 30 &
  HAND_OPENED_BTOP_PID=$!
  disown
  mock_bin btop <<EOF
#!/bin/bash
echo "btop version: $version"
EOF
  mock_bin pkill <<'EOF'
#!/bin/bash
mock_log "pkill $*"
EOF
  mock_bin pgrep <<EOF
#!/bin/bash
case "\$*" in
  *-f*) echo 999999 ;;
  *-P*) echo "$WINDOW_BTOP_PID" ;;
esac
EOF
  sed -e "s#/usr/bin/btop#$MOCK_BIN/btop#g" "$SCRIPT" >"$MOCK_DIR/theme-set-btop-patched.sh"
  PATH="$(mock_path)" bash "$MOCK_DIR/theme-set-btop-patched.sh" >/dev/null 2>&1
  sleep 0.3
}

assert_fallback_outcome() {
  local label="$1"
  local window_state="dead" hand_opened_state="dead"
  kill -0 "$WINDOW_BTOP_PID" 2>/dev/null && window_state="still alive"
  kill -0 "$HAND_OPENED_BTOP_PID" 2>/dev/null && hand_opened_state="still alive"
  assert_eq "$label: window's btop signaled (ohmydebn-btop-run restarts it in place)" "dead" "$window_state"
  assert_eq "$label: hand-opened btop left alone" "still alive" "$hand_opened_state"
  assert_not_contains "$label: broad pkill not used" "$(cat "$MOCK_CALLS")" "pkill"
  kill "$HAND_OPENED_BTOP_PID" 2>/dev/null
  wait "$WINDOW_BTOP_PID" "$HAND_OPENED_BTOP_PID" 2>/dev/null
}

mock_init
run_fallback_with_running_window "1.3.0"
assert_fallback_outcome "old btop, window running"
mock_cleanup

mock_init
run_fallback_with_running_window ""
assert_fallback_outcome "unparseable version, window running"
mock_cleanup

# No hotkey btop window currently running (pgrep -f finds nothing) - the
# fallback must not signal anything at all.
mock_init
sleep 30 &
HAND_OPENED_BTOP_PID=$!
disown
mock_bin btop <<'EOF'
#!/bin/bash
echo "btop version: 1.3.0"
EOF
mock_bin pkill <<'EOF'
#!/bin/bash
mock_log "pkill $*"
EOF
mock_bin pgrep <<EOF
#!/bin/bash
case "\$*" in
  *-f*) true ;;
  *-P*) echo "$HAND_OPENED_BTOP_PID" ;;
esac
EOF
sed -e "s#/usr/bin/btop#$MOCK_BIN/btop#g" "$SCRIPT" >"$MOCK_DIR/theme-set-btop-patched.sh"
PATH="$(mock_path)" bash "$MOCK_DIR/theme-set-btop-patched.sh" >/dev/null 2>&1
sleep 0.3
HAND_OPENED_STATE="dead"
kill -0 "$HAND_OPENED_BTOP_PID" 2>/dev/null && HAND_OPENED_STATE="still alive"
assert_eq "old btop, no window running: nothing signaled" "still alive" "$HAND_OPENED_STATE"
assert_not_contains "old btop, no window running: broad pkill not used" "$(cat "$MOCK_CALLS")" "pkill"
kill "$HAND_OPENED_BTOP_PID" 2>/dev/null
wait "$HAND_OPENED_BTOP_PID" 2>/dev/null
mock_cleanup

test_summary
