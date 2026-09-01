#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-btop's version gate on the SIGUSR2
# hot-reload signal, and the kill+relaunch fallback for btop versions that
# can't hot-reload. Added after a live-VM report: btop's SIGUSR2 hot-reload
# handler was only added upstream in 1.3.1 (changelog: "Add hot-reloading
# of config file with CTRL+R or SIGUSR2 signal") - on any older btop the
# signal has no registered handler and falls back to its POSIX default
# action (terminate), which killed btop out from under its
# `alacritty -e btop` window (no --hold) the instant a theme was applied,
# on a machine running btop 1.3.0. `pkill` itself is mocked purely to
# record whether it was invoked at all - the gate must skip the call
# entirely below 1.3.1, not just no-op it.
#
# For the fallback branch (too old / unparseable version): rather than
# leave that window showing stale colors forever, the script kills and
# relaunches the tiled hotkey's own btop window. `kill` is a bash builtin
# (can't be mocked via PATH), so those scenarios spawn a real short-lived
# background process to stand in for the window's alacritty process and
# check whether it actually got terminated, rather than mocking the kill.

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
  mock_bin ohmydebn-btop-gui <<'EOF'
#!/bin/bash
mock_log "relaunched"
EOF
  sed -e "s#/usr/bin/btop#$MOCK_BIN/btop#g" \
      -e "s#/usr/share/ohmydebn/bin/ohmydebn-btop-gui#$MOCK_BIN/ohmydebn-btop-gui#g" \
      "$SCRIPT" >"$MOCK_DIR/theme-set-btop-patched.sh"
  PATH="$(mock_path)" bash "$MOCK_DIR/theme-set-btop-patched.sh" >/dev/null 2>&1
}

mock_init
run_with_btop_version "1.3.0"
assert_not_contains "btop 1.3.0 (pre-hot-reload): SIGUSR2 not sent" "$(cat "$MOCK_CALLS")" "pkill"
mock_cleanup

mock_init
run_with_btop_version "1.3.1"
assert_contains "btop 1.3.1 (hot-reload added): SIGUSR2 sent" "$(cat "$MOCK_CALLS")" "pkill -SIGUSR2 btop"
assert_not_contains "btop 1.3.1: fallback path not taken" "$(cat "$MOCK_CALLS")" "pgrep"
mock_cleanup

mock_init
run_with_btop_version "1.3.2"
assert_contains "btop 1.3.2 (newer than hot-reload): SIGUSR2 sent" "$(cat "$MOCK_CALLS")" "pkill -SIGUSR2 btop"
mock_cleanup

mock_init
run_with_btop_version "1.2.13"
assert_not_contains "btop 1.2.13 (much older): SIGUSR2 not sent" "$(cat "$MOCK_CALLS")" "pkill"
mock_cleanup

mock_init
run_with_btop_version "2.0.0"
assert_contains "btop 2.0.0 (future major): SIGUSR2 sent" "$(cat "$MOCK_CALLS")" "pkill -SIGUSR2 btop"
mock_cleanup

# btop missing/unparseable --version output: skip signaling rather than
# guess, same as the "too old" branches above.
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
assert_not_contains "unparseable --version: SIGUSR2 not sent" "$(cat "$MOCK_CALLS")" "pkill"
mock_cleanup

# --- kill+relaunch fallback (no confirmed hot-reload support) ---

# pgrep is mocked here to stand in for the real process tree: -f returns a
# fake wrapper PID, -P returns ALACRITTY_PID regardless of which wrapper
# PID was asked about. A real background process plays the alacritty
# child's role so termination can be observed directly with kill -0,
# rather than trusting that `kill` was merely called with the right PID.
run_fallback_with_running_window() {
  local version="$1"
  sleep 30 &
  ALACRITTY_PID=$!
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
  *-P*) echo "$ALACRITTY_PID" ;;
esac
EOF
  mock_bin ohmydebn-btop-gui <<'EOF'
#!/bin/bash
mock_log "relaunched"
EOF
  sed -e "s#/usr/bin/btop#$MOCK_BIN/btop#g" \
      -e "s#/usr/share/ohmydebn/bin/ohmydebn-btop-gui#$MOCK_BIN/ohmydebn-btop-gui#g" \
      "$SCRIPT" >"$MOCK_DIR/theme-set-btop-patched.sh"
  PATH="$(mock_path)" bash "$MOCK_DIR/theme-set-btop-patched.sh" >/dev/null 2>&1
  sleep 0.3
}

mock_init
run_fallback_with_running_window "1.3.0"
ALACRITTY_STATE="dead"
kill -0 "$ALACRITTY_PID" 2>/dev/null && ALACRITTY_STATE="still alive"
assert_eq "old btop, window running: alacritty child killed" "dead" "$ALACRITTY_STATE"
assert_contains "old btop, window running: fresh window relaunched" "$(cat "$MOCK_CALLS")" "relaunched"
wait "$ALACRITTY_PID" 2>/dev/null
mock_cleanup

mock_init
run_fallback_with_running_window ""
ALACRITTY_STATE="dead"
kill -0 "$ALACRITTY_PID" 2>/dev/null && ALACRITTY_STATE="still alive"
assert_eq "unparseable version, window running: alacritty child killed" "dead" "$ALACRITTY_STATE"
assert_contains "unparseable version, window running: fresh window relaunched" "$(cat "$MOCK_CALLS")" "relaunched"
wait "$ALACRITTY_PID" 2>/dev/null
mock_cleanup

# No tiled btop window currently running (pgrep -f finds nothing) - the
# fallback must not relaunch a window nobody asked for.
mock_init
mock_bin btop <<'EOF'
#!/bin/bash
echo "btop version: 1.3.0"
EOF
mock_bin pkill <<'EOF'
#!/bin/bash
mock_log "pkill $*"
EOF
mock_bin pgrep <<'EOF'
#!/bin/bash
true
EOF
mock_bin ohmydebn-btop-gui <<'EOF'
#!/bin/bash
mock_log "relaunched"
EOF
sed -e "s#/usr/bin/btop#$MOCK_BIN/btop#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-btop-gui#$MOCK_BIN/ohmydebn-btop-gui#g" \
    "$SCRIPT" >"$MOCK_DIR/theme-set-btop-patched.sh"
PATH="$(mock_path)" bash "$MOCK_DIR/theme-set-btop-patched.sh" >/dev/null 2>&1
assert_not_contains "old btop, no window running: nothing relaunched" "$(cat "$MOCK_CALLS")" "relaunched"
mock_cleanup

test_summary
