#!/bin/bash
#
# Unit tests for bin/ohmydebn-fastfetch-pause's own pidfile lifecycle and
# SIGUSR2 re-render trap, added alongside ohmydebn-theme-set-fastfetch's new
# refresh-in-place behavior. test-theme-set-fastfetch.sh already covers the
# sending side (against a fake stand-in process) - these exercise the real
# script itself: does it actually write its PID where the sender expects,
# does SIGUSR2 actually trigger a second render, and is the pidfile cleaned
# up on exit so a later sender's /proc/*/cmdline guard doesn't need to.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-fastfetch-pause"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-fastfetch-pause ==="

mock_init
mock_bin ohmydebn-fastfetch <<'EOF'
#!/bin/bash
mock_log "rendered"
EOF
sed -e "s#/usr/share/ohmydebn/bin/ohmydebn-fastfetch#$MOCK_BIN/ohmydebn-fastfetch#" \
  "$SCRIPT" >"$MOCK_DIR/fastfetch-pause-patched.sh"

SCRATCH_HOME=$(mktemp -d)
PID_FILE="$SCRATCH_HOME/.cache/ohmydebn/fastfetch-pause.pid"
# A terminal stand-in for the windows' input: a FIFO held open and never
# written, so their key reads time out as they do at a real terminal (the
# script ends at end-of-input).
mkfifo "$MOCK_DIR/tty"
exec 3<>"$MOCK_DIR/tty"
HOME="$SCRATCH_HOME" bash "$MOCK_DIR/fastfetch-pause-patched.sh" <&3 >/dev/null 2>&1 &
WRAPPER_PID=$!
sleep 0.3

assert_eq "pidfile holds this process's own PID" "$WRAPPER_PID" "$(cat "$PID_FILE" 2>/dev/null)"
assert_contains "renders once on start" "$(cat "$MOCK_CALLS")" "rendered"

kill -SIGUSR2 "$WRAPPER_PID"
sleep 0.3
assert_eq "SIGUSR2 triggers a second render" "2" "$(grep -c rendered "$MOCK_CALLS")"

kill "$WRAPPER_PID" 2>/dev/null
wait "$WRAPPER_PID" 2>/dev/null
sleep 0.2
PID_FILE_STATE="gone"
[ -f "$PID_FILE" ] && PID_FILE_STATE="still present"
assert_eq "pidfile removed on exit" "gone" "$PID_FILE_STATE"

# Two windows: the second's PID is in the file, and the first closing
# must leave it, or a theme change no longer refreshes the one still open.
HOME="$SCRATCH_HOME" bash "$MOCK_DIR/fastfetch-pause-patched.sh" <&3 >/dev/null 2>&1 &
FIRST_PID=$!
sleep 0.3
HOME="$SCRATCH_HOME" bash "$MOCK_DIR/fastfetch-pause-patched.sh" <&3 >/dev/null 2>&1 &
SECOND_PID=$!
sleep 0.3
kill "$FIRST_PID" 2>/dev/null
wait "$FIRST_PID" 2>/dev/null
sleep 0.2
assert_eq "two windows: closing the first keeps the second's pidfile" "$SECOND_PID" "$(cat "$PID_FILE" 2>/dev/null)"
kill "$SECOND_PID" 2>/dev/null
wait "$SECOND_PID" 2>/dev/null

# End of input closes the window, rather than spinning on it.
HOME="$SCRATCH_HOME" timeout 5 bash "$MOCK_DIR/fastfetch-pause-patched.sh" </dev/null >/dev/null 2>&1
assert_eq "end of input closes the window" "0" "$?"

exec 3<&-
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
