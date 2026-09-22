#!/bin/bash
#
# Unit tests for the theme-change refresh of an open logo window: the
# pidfile lifecycle and SIGUSR2 re-render trap in bin/ohmydebn-logo (the
# receiving side, with toilet/ttfx/the color helper mocked), and
# bin/ohmydebn-theme-set-logo (the sending side, against a stand-in
# process). Mirrors test-fastfetch-pause.sh and test-theme-set-fastfetch.sh;
# see those for why a real background process is used rather than mocking
# `kill` (a bash builtin, so PATH can't reach it).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOGO="$REPO_ROOT/bin/ohmydebn-logo"
SENDER="$REPO_ROOT/bin/ohmydebn-theme-set-logo"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-logo / bin/ohmydebn-theme-set-logo (SIGUSR2 refresh) ==="

# --- receiving side: the real ohmydebn-logo, its render pipeline mocked ---
mock_init
mock_bin ohmydebn-logo-generate <<'EOF2'
#!/bin/bash
exit 0
EOF2
mock_bin ohmydebn-theme-logo-colors <<'EOF2'
#!/bin/bash
echo "rain=#111111 #222222"
echo "gradient=#333333 #444444"
EOF2
mock_bin toilet <<'EOF2'
#!/bin/bash
echo "LOGO"
EOF2
mock_bin ttfx <<'EOF2'
#!/bin/bash
cat >/dev/null
mock_log "rendered $*"
EOF2
mock_bin clear <<'EOF2'
#!/bin/bash
exit 0
EOF2
sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/bin/ttfx#$MOCK_BIN/ttfx#g" "$LOGO" >"$MOCK_DIR/logo-patched.sh"

SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/branding"
echo "OhMyDebn" >"$SCRATCH_HOME/.config/ohmydebn/branding/name.txt"
PID_FILE="$SCRATCH_HOME/.cache/ohmydebn/logo.pid"
# Stdin from a FIFO held open (not /dev/null): with EOF on stdin the
# any-key loop would exit at once, as a real closed pty would.
FIFO="$MOCK_DIR/stdin"; mkfifo "$FIFO"
exec 7<>"$FIFO"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/logo-patched.sh" <&7 >/dev/null 2>&1 &
LOGO_PID=$!
sleep 0.4

assert_eq "pidfile holds the logo process's own PID" "$LOGO_PID" "$(cat "$PID_FILE" 2>/dev/null)"
assert_eq "renders once on start, with the theme's colors" "1" "$(grep -c 'rendered rain --rain-colors #111111 #222222 --final-gradient-stops #333333 #444444' "$MOCK_CALLS")"

kill -SIGUSR2 "$LOGO_PID"
sleep 0.4
assert_eq "SIGUSR2 replays the animation" "2" "$(grep -c rendered "$MOCK_CALLS")"
assert_eq "SIGUSR2 doesn't close the window" "yes" "$(kill -0 "$LOGO_PID" 2>/dev/null && echo yes || echo no)"

# A keypress ends it, as before.
echo -n x >&7
sleep 0.8
assert_eq "a key closes the window" "no" "$(kill -0 "$LOGO_PID" 2>/dev/null && echo yes || echo no)"
wait "$LOGO_PID" 2>/dev/null
assert_eq "pidfile removed on exit" "gone" "$([ -f "$PID_FILE" ] && echo 'still present' || echo gone)"
exec 7>&-
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- sending side, scenario 1: a live process whose cmdline contains "ohmydebn-logo" gets signaled ---
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.cache/ohmydebn"
RECEIVED_FILE="$MOCK_DIR/received"
: >"$RECEIVED_FILE"
FAKE_SCRIPT="$MOCK_BIN/ohmydebn-logo"
cat >"$FAKE_SCRIPT" <<EOF2
#!/bin/bash
trap 'echo signaled >>"$RECEIVED_FILE"' USR2
sleep 5 &
wait \$!
EOF2
chmod +x "$FAKE_SCRIPT"
"$FAKE_SCRIPT" &
FAKE_PID=$!
echo "$FAKE_PID" >"$SCRATCH_HOME/.cache/ohmydebn/logo.pid"
sleep 0.3
HOME="$SCRATCH_HOME" bash "$SENDER" >/dev/null 2>&1
sleep 0.3
assert_contains "sender, live matching process: SIGUSR2 delivered" "$(cat "$RECEIVED_FILE")" "signaled"
kill "$FAKE_PID" 2>/dev/null
wait "$FAKE_PID" 2>/dev/null
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- sending side, scenario 2: stale pidfile pointing at a foreign live PID (this test's own) - not signaled ---
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.cache/ohmydebn"
RECEIVED=""
trap 'RECEIVED=1' USR2
echo "$$" >"$SCRATCH_HOME/.cache/ohmydebn/logo.pid"
HOME="$SCRATCH_HOME" bash "$SENDER" >/dev/null 2>&1
sleep 0.3
assert_eq "sender, stale pidfile (foreign process): SIGUSR2 not sent" "" "$RECEIVED"
trap - USR2
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- sending side, scenario 3: no pidfile (logo window never opened) - exits cleanly ---
mock_init
SCRATCH_HOME=$(mktemp -d)
HOME="$SCRATCH_HOME" bash "$SENDER" >/dev/null 2>&1
assert_eq "sender, no pidfile: exits cleanly" "0" "$?"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
