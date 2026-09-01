#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-fastfetch's SIGUSR2 refresh of an
# already-open ohmydebn-fastfetch-gui window (bin/ohmydebn-fastfetch-pause).
# `kill` is a bash builtin, so it can't be mocked via PATH like pkill is for
# btop/cava - these spawn a real short-lived background process and check
# whether it actually received SIGUSR2, rather than mocking the signal send.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-fastfetch"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-fastfetch (SIGUSR2 refresh) ==="

run_theme_set_fastfetch() {
  local scratch_home="$1"
  HOME="$scratch_home" bash "$SCRIPT" >/dev/null 2>&1
}

# Scenario 1: a live process whose cmdline contains "ohmydebn-fastfetch-pause"
# (standing in for the real process) gets signaled.
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.cache/ohmydebn"
RECEIVED_FILE="$MOCK_DIR/received"
: >"$RECEIVED_FILE"
FAKE_SCRIPT="$MOCK_BIN/ohmydebn-fastfetch-pause"
cat >"$FAKE_SCRIPT" <<EOF
#!/bin/bash
# "sleep & wait", not a bare sleep or read -t: bash only runs a pending
# trap promptly while blocked in a builtin wait, so a backgrounded sleep
# reaped via \`wait\` is the standard interruptible-sleep idiom. A bare
# external sleep defers the trap until it exits on its own. read -t would
# work too in the real ohmydebn-fastfetch-pause (which always runs under a
# real pty) but returns instantly on EOF here, since this test has no
# controlling tty for the backgrounded process to read from.
trap 'echo signaled >>"$RECEIVED_FILE"' USR2
sleep 5 &
wait \$!
EOF
chmod +x "$FAKE_SCRIPT"
"$FAKE_SCRIPT" &
FAKE_PID=$!
echo "$FAKE_PID" >"$SCRATCH_HOME/.cache/ohmydebn/fastfetch-pause.pid"
# Give the background process time to reach its own trap line - signaling
# before that registers would hit SIGUSR2's default action (terminate)
# instead, since no handler is registered yet.
sleep 0.3
run_theme_set_fastfetch "$SCRATCH_HOME"
sleep 0.3
assert_contains "live matching process: SIGUSR2 delivered" "$(cat "$RECEIVED_FILE")" "signaled"
kill "$FAKE_PID" 2>/dev/null
wait "$FAKE_PID" 2>/dev/null
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: a stale pidfile pointing at a live PID that ISN'T
# ohmydebn-fastfetch-pause (e.g. reused by an unrelated process since) must
# not be signaled - use this test script's own PID as the foreign process.
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.cache/ohmydebn"
RECEIVED=""
trap 'RECEIVED=1' USR2
echo "$$" >"$SCRATCH_HOME/.cache/ohmydebn/fastfetch-pause.pid"
run_theme_set_fastfetch "$SCRATCH_HOME"
sleep 0.3
assert_eq "stale pidfile (foreign process): SIGUSR2 not sent" "" "$RECEIVED"
trap - USR2
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: no pidfile at all (fastfetch window never opened this session)
# - script must not error out.
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.cache/ohmydebn"
HOME="$SCRATCH_HOME" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "no pidfile: script exits cleanly" "0" "$?"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
