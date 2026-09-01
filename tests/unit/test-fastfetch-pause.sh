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
HOME="$SCRATCH_HOME" bash "$MOCK_DIR/fastfetch-pause-patched.sh" >/dev/null 2>&1 &
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

rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
