#!/bin/bash
#
# Unit tests for bin/ohmydebn-lock, the lock command Cinnamon runs with the
# XScreenSaver lock screen. xscreensaver-command, the daemon starter,
# Cinnamon's screensaver and gdbus are mocked; the mock xscreensaver keeps
# its state (running, locked) in files, so each path can be driven: already
# running, started on demand, never locking (the fallback to Cinnamon's
# screensaver), and the suspend lock descriptor kept from the daemons.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-lock"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-lock ==="

setup() {
  mock_init
  # The real script, with OhMyDebn's paths at the mocks and short waits.
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#^START_WAIT_TENTHS=.*#START_WAIT_TENTHS=5#; s#^LOCK_WAIT_TENTHS=.*#LOCK_WAIT_TENTHS=5#; s#^FALLBACK_WAIT_TENTHS=.*#FALLBACK_WAIT_TENTHS=5#" \
    "$SCRIPT" >"$MOCK_DIR/ohmydebn-lock"
  mock_bin xscreensaver-command <<'EOF2'
#!/bin/bash
case "$1" in
--version) [ -e "$MOCK_DIR/running" ] ;;
--lock)
  mock_log "xscreensaver-command --lock"
  [ -e "$MOCK_DIR/running" ] && [ ! -e "$MOCK_DIR/lock-fails" ] && : >"$MOCK_DIR/locked"
  exit 0
  ;;
--time)
  if [ -e "$MOCK_DIR/locked" ]; then echo "XScreenSaver 6.09: screen locked since Sat Nov  7 10:00:00 2026"
  else echo "XScreenSaver 6.09: screen non-blanked since Sat Nov  7 09:00:00 2026"; fi
  ;;
esac
EOF2
  # The daemon starter records whether the suspend lock descriptor reached
  # it, then "starts" XScreenSaver unless told not to.
  mock_bin ohmydebn-xscreensaver-start <<'EOF2'
#!/bin/bash
if [ -n "${XSS_SLEEP_LOCK_FD:-}" ] && [ -e "/proc/self/fd/$XSS_SLEEP_LOCK_FD" ]; then
  mock_log "start (sleep lock fd open)"
else
  mock_log "start"
fi
[ -e "$MOCK_DIR/start-fails" ] || : >"$MOCK_DIR/running"
EOF2
  mock_bin cinnamon-screensaver <<'EOF2'
#!/bin/bash
mock_log "cinnamon-screensaver GSETTINGS_BACKEND=${GSETTINGS_BACKEND:-}"
: >"$MOCK_DIR/cs-up"
EOF2
  mock_bin gdbus <<'EOF2'
#!/bin/bash
case "$*" in
*NameHasOwner*) [ -e "$MOCK_DIR/cs-up" ] && echo "(true,)" || echo "(false,)" ;;
*org.cinnamon.ScreenSaver.Lock*)
  mock_log "gdbus Lock"
  [ -e "$MOCK_DIR/cs-lock-fails" ] && exit 1
  ;;
esac
exit 0
EOF2
  mock_bin notify-send <<'EOF2'
#!/bin/bash
mock_log "notify-send $*"
EOF2
}

run_lock() {
  OUTPUT=$(env PATH="$(mock_path)" "$@" bash "$MOCK_DIR/ohmydebn-lock" </dev/null 2>&1)
  EXIT_CODE=$?
  CALLS=$(cat "$MOCK_CALLS")
}

# --- XScreenSaver running: it locks, and nothing else happens ---
setup
: >"$MOCK_DIR/running"
run_lock
assert_eq "running: exits 0" "0" "$EXIT_CODE"
assert_contains "running: asks XScreenSaver to lock" "$CALLS" "xscreensaver-command --lock"
assert_not_contains "running: doesn't start another daemon" "$CALLS" "start"
assert_not_contains "running: no fallback" "$CALLS" "cinnamon-screensaver"
assert_not_contains "running: no notification" "$CALLS" "notify-send"
assert_eq "running: prints nothing (Cinnamon runs it with no terminal)" "" "$OUTPUT"
mock_cleanup

# --- not running: started first, then locked ---
setup
run_lock
assert_eq "not running: exits 0" "0" "$EXIT_CODE"
assert_contains "not running: starts XScreenSaver" "$CALLS" "start"
assert_contains "not running: then locks" "$CALLS" "xscreensaver-command --lock"
assert_eq "not running: start comes before the lock" "start" "$(head -1 "$MOCK_CALLS")"
assert_not_contains "not running: no fallback" "$CALLS" "cinnamon-screensaver"
mock_cleanup

# --- before suspend: the daemon it starts doesn't keep the sleep lock ---
setup
exec 9>"$MOCK_DIR/sleep-lock"
run_lock XSS_SLEEP_LOCK_FD=9
exec 9>&-
assert_eq "sleep lock: exits 0" "0" "$EXIT_CODE"
assert_contains "sleep lock: daemon started" "$CALLS" "start"
assert_not_contains "sleep lock: the daemon didn't get the descriptor" "$CALLS" "sleep lock fd open"
mock_cleanup

# --- XScreenSaver never locks: Cinnamon's screensaver locks instead ---
setup
: >"$MOCK_DIR/running"
: >"$MOCK_DIR/lock-fails"
run_lock
assert_eq "never locks: exits 0 (the fallback locked)" "0" "$EXIT_CODE"
assert_contains "never locks: starts Cinnamon's screensaver with default settings" "$CALLS" "cinnamon-screensaver GSETTINGS_BACKEND=memory"
assert_contains "never locks: asks it to lock over D-Bus" "$CALLS" "gdbus Lock"
assert_contains "never locks: says so" "$CALLS" "notify-send -i ohmydebn -u critical Lock screen XScreenSaver didn't lock the screen"
mock_cleanup

# --- XScreenSaver won't start, Cinnamon's screensaver already running ---
setup
: >"$MOCK_DIR/start-fails"
: >"$MOCK_DIR/cs-up"
run_lock
assert_eq "won't start: exits 0" "0" "$EXIT_CODE"
assert_not_contains "won't start: doesn't start a second Cinnamon screensaver" "$CALLS" "cinnamon-screensaver GSETTINGS"
assert_contains "won't start: the running one locks" "$CALLS" "gdbus Lock"
mock_cleanup

# --- nothing can lock: fails, and still says so ---
setup
: >"$MOCK_DIR/start-fails"
: >"$MOCK_DIR/cs-lock-fails"
run_lock
assert_eq "nothing locks: exits 1" "1" "$EXIT_CODE"
assert_contains "nothing locks: notification still sent" "$CALLS" "notify-send"
mock_cleanup

test_summary
