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
--activate)
  mock_log "xscreensaver-command --activate"
  [ -e "$MOCK_DIR/running" ] && [ ! -e "$MOCK_DIR/activate-fails" ] && : >"$MOCK_DIR/blanked"
  exit 0
  ;;
--time)
  if [ -e "$MOCK_DIR/locked" ]; then echo "XScreenSaver 6.09: screen locked since Sat Nov  7 10:00:00 2026"
  elif [ -e "$MOCK_DIR/blanked" ]; then echo "XScreenSaver 6.09: screen blanked since Sat Nov  7 10:00:00 2026"
  else echo "XScreenSaver 6.09: screen non-blanked since Sat Nov  7 09:00:00 2026"; fi
  ;;
esac
EOF2
  # Cinnamon's screensaver settings: lock-enabled and lock-delay, or no
  # answer at all.
  mock_bin gsettings <<'EOF2'
#!/bin/bash
[ -n "${MOCK_GSETTINGS_FAILS:-}" ] && exit 1
case "$*" in
*lock-enabled) echo "${MOCK_LOCK_ENABLED:-true}" ;;
*lock-delay) echo "uint32 ${MOCK_LOCK_DELAY:-0}" ;;
esac
EOF2
  # The grace period's lock runs ohmydebn-lock again; this stands in for it.
  mock_bin ohmydebn-lock <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-lock again LOCKED_BY_SESSION_IDLE=${LOCKED_BY_SESSION_IDLE:-unset}"
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
  # Like the real one: success even when it couldn't grab the keyboard
  # (another app holds it, such as a virtual machine window), with
  # nothing locked.
  [ -e "$MOCK_DIR/cs-grab-fails" ] || : >"$MOCK_DIR/cs-active"
  ;;
*org.cinnamon.ScreenSaver.GetActive*) [ -e "$MOCK_DIR/cs-active" ] && echo "(true,)" || echo "(false,)" ;;
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

# --- XScreenSaver reports the lock late (a fade), but within the wait:
# no fallback. The mock reports it from its fourth --time on, about half a
# second in, inside this test's shortened wait. ---
setup
: >"$MOCK_DIR/running"
mock_bin xscreensaver-command <<'EOF2'
#!/bin/bash
case "$1" in
--version) exit 0 ;;
--lock) mock_log "xscreensaver-command --lock" ;;
--time)
  n=$(($(cat "$MOCK_DIR/time-calls" 2>/dev/null || echo 0) + 1))
  echo "$n" >"$MOCK_DIR/time-calls"
  if [ "$n" -ge 4 ]; then echo "XScreenSaver 6.09: screen locked since Sat Nov  7 10:00:00 2026"
  else echo "XScreenSaver 6.09: screen blanked since Sat Nov  7 10:00:00 2026"; fi
  ;;
esac
EOF2
run_lock
assert_eq "late lock: exits 0" "0" "$EXIT_CODE"
assert_not_contains "late lock: no fallback" "$CALLS" "cinnamon-screensaver"
assert_not_contains "late lock: no notification" "$CALLS" "notify-send"
mock_cleanup

# --- the real wait outlasts XScreenSaver's default 3-second fade, with
# room to spare, so a fade a user turned back on isn't taken for a failure ---
LOCK_WAIT=$(sed -n 's/^LOCK_WAIT_TENTHS=//p' "$SCRIPT")
assert_eq "wait: at least 10 seconds" "yes" "$([ "${LOCK_WAIT:-0}" -ge 100 ] && echo yes || echo no)"

# --- XScreenSaver never locks: Cinnamon's screensaver locks instead ---
setup
: >"$MOCK_DIR/running"
: >"$MOCK_DIR/lock-fails"
run_lock
assert_eq "never locks: exits 0 (the fallback locked)" "0" "$EXIT_CODE"
assert_contains "never locks: starts Cinnamon's screensaver with default settings" "$CALLS" "cinnamon-screensaver GSETTINGS_BACKEND=memory"
assert_contains "never locks: asks it to lock over D-Bus" "$CALLS" "gdbus Lock"
assert_contains "never locks: says Cinnamon's screensaver locked it" "$CALLS" "notify-send -i ohmydebn -u critical Lock screen XScreenSaver couldn't lock the screen, so Cinnamon's screensaver locked it instead"
assert_contains "never locks: names the likely cause" "$CALLS" "such as a virtual machine window"
assert_not_contains "never locks: doesn't say the screen is open" "$CALLS" "Screen not locked"
mock_cleanup

# --- another app holds the keyboard (a virtual machine window): neither
# can lock. Cinnamon's screensaver still answers Lock with success, so
# only asking whether it's active shows it isn't. Seen on a desktop with
# a VM window focused: the notice said the screen was locked, and it
# wasn't. ---
setup
: >"$MOCK_DIR/running"
: >"$MOCK_DIR/lock-fails"
: >"$MOCK_DIR/cs-grab-fails"
run_lock
assert_eq "keyboard held: exits 1 (nothing locked)" "1" "$EXIT_CODE"
assert_contains "keyboard held: tried Cinnamon's screensaver" "$CALLS" "gdbus Lock"
assert_contains "keyboard held: says the screen isn't locked" "$CALLS" "notify-send -i ohmydebn -u critical Screen not locked Your screen wasn't locked"
assert_not_contains "keyboard held: doesn't claim a lock" "$CALLS" "locked it instead"
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

# --- idle timeout, locking turned off in Cinnamon: blank, no lock ---
setup
: >"$MOCK_DIR/running"
run_lock LOCKED_BY_SESSION_IDLE=true MOCK_LOCK_ENABLED=false
assert_eq "idle, no lock: exits 0" "0" "$EXIT_CODE"
assert_contains "idle, no lock: blanks" "$CALLS" "xscreensaver-command --activate"
assert_not_contains "idle, no lock: doesn't lock" "$CALLS" "--lock"
assert_not_contains "idle, no lock: no fallback" "$CALLS" "cinnamon-screensaver"
mock_cleanup

# --- idle timeout, locking on with no grace period: locks at once ---
setup
: >"$MOCK_DIR/running"
run_lock LOCKED_BY_SESSION_IDLE=true MOCK_LOCK_ENABLED=true MOCK_LOCK_DELAY=0
assert_contains "idle, lock: locks" "$CALLS" "xscreensaver-command --lock"
assert_not_contains "idle, lock: doesn't just blank" "$CALLS" "--activate"
mock_cleanup

# --- idle timeout with a 1-second grace period: blanks, then locks if the
# screen is still blank ---
setup
: >"$MOCK_DIR/running"
run_lock LOCKED_BY_SESSION_IDLE=true MOCK_LOCK_ENABLED=true MOCK_LOCK_DELAY=1
assert_eq "grace: exits 0 once blank, without waiting" "0" "$EXIT_CODE"
assert_contains "grace: blanks first" "$CALLS" "xscreensaver-command --activate"
assert_not_contains "grace: no lock yet" "$CALLS" "ohmydebn-lock again"
sleep 1.6
assert_contains "grace: locks after the grace period, as an ordinary lock" "$(cat "$MOCK_CALLS")" "ohmydebn-lock again LOCKED_BY_SESSION_IDLE=unset"
mock_cleanup

# --- grace period, but the user came back first: no lock ---
setup
: >"$MOCK_DIR/running"
run_lock LOCKED_BY_SESSION_IDLE=true MOCK_LOCK_ENABLED=true MOCK_LOCK_DELAY=1
rm -f "$MOCK_DIR/blanked"
sleep 1.6
assert_not_contains "grace, activity: no lock" "$(cat "$MOCK_CALLS")" "ohmydebn-lock again"
mock_cleanup

# --- idle timeout, settings unreadable: lock, the safe side ---
setup
: >"$MOCK_DIR/running"
run_lock LOCKED_BY_SESSION_IDLE=true MOCK_GSETTINGS_FAILS=1
assert_contains "idle, no settings: locks" "$CALLS" "xscreensaver-command --lock"
mock_cleanup

# --- before suspend (false), even with idle locking off: locks ---
setup
: >"$MOCK_DIR/running"
run_lock LOCKED_BY_SESSION_IDLE=false MOCK_LOCK_ENABLED=false
assert_contains "suspend: locks whatever the idle setting" "$CALLS" "xscreensaver-command --lock"
mock_cleanup

# --- blank only, and blanking fails: fails quietly, no lock was asked for ---
setup
: >"$MOCK_DIR/running"
: >"$MOCK_DIR/activate-fails"
run_lock LOCKED_BY_SESSION_IDLE=true MOCK_LOCK_ENABLED=false
assert_eq "blank fails: exits 1" "1" "$EXIT_CODE"
assert_not_contains "blank fails: no fallback lock" "$CALLS" "cinnamon-screensaver"
assert_not_contains "blank fails: no notification" "$CALLS" "notify-send"
mock_cleanup

# --- grace period due, and blanking fails: the lock still happens ---
setup
: >"$MOCK_DIR/running"
: >"$MOCK_DIR/activate-fails"
run_lock LOCKED_BY_SESSION_IDLE=true MOCK_LOCK_ENABLED=true MOCK_LOCK_DELAY=30
assert_contains "grace, blank fails: falls back to locking" "$CALLS" "gdbus Lock"
mock_cleanup

# --- nothing can lock: fails, and still says so ---
setup
: >"$MOCK_DIR/start-fails"
: >"$MOCK_DIR/cs-lock-fails"
run_lock
assert_eq "nothing locks: exits 1" "1" "$EXIT_CODE"
assert_contains "nothing locks: says the screen isn't locked" "$CALLS" "Screen not locked"
assert_not_contains "nothing locks: doesn't claim a lock" "$CALLS" "locked it instead"
mock_cleanup

test_summary
