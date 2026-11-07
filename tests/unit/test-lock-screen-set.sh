#!/bin/bash
#
# Unit tests for bin/ohmydebn-lock-screen-set, which switches the lock
# screen between Cinnamon's and XScreenSaver. gsettings keeps the
# custom-screensaver-command value in a file; the installer, theme hook,
# daemon starter, xscreensaver-command, Cinnamon's screensaver and gdbus are
# mocked; HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-lock-screen-set"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-lock-screen-set ==="

LOCK_COMMAND=/usr/share/ohmydebn/bin/ohmydebn-lock

setup() {
  mock_init
  H="$MOCK_DIR/home"
  mkdir -p "$H"
  # Only the installer and hook, and the daemon it starts now, point at the
  # mocks: LOCK_COMMAND and the autostart entry's Exec are values written
  # for Cinnamon, and must stay the real paths.
  sed "s#/usr/share/ohmydebn/bin/ohmydebn-xscreensaver-install#$MOCK_BIN/ohmydebn-xscreensaver-install#; s#/usr/share/ohmydebn/bin/ohmydebn-theme-set-xscreensaver#$MOCK_BIN/ohmydebn-theme-set-xscreensaver#; s#setsid /usr/share/ohmydebn/bin/ohmydebn-xscreensaver-start#setsid $MOCK_BIN/ohmydebn-xscreensaver-start#" \
    "$SCRIPT" >"$MOCK_DIR/ohmydebn-lock-screen-set"
  : >"$MOCK_DIR/custom"
  mock_bin gsettings <<'EOF2'
#!/bin/bash
case "$1" in
get) v=$(cat "$MOCK_DIR/custom"); echo "'$v'" ;;
set) mock_log "gsettings set $2 $3 $4"; printf '%s' "$4" >"$MOCK_DIR/custom" ;;
reset) mock_log "gsettings reset $2 $3"; : >"$MOCK_DIR/custom" ;;
esac
EOF2
  for m in ohmydebn-xscreensaver-install ohmydebn-theme-set-xscreensaver ohmydebn-xscreensaver-start cinnamon-screensaver notify-send; do
    mock_bin "$m" <<'EOF2'
#!/bin/bash
mock_log "$(basename "$0") $*"
EOF2
  done
  mock_bin gdbus <<'EOF2'
#!/bin/bash
mock_log "gdbus ${*: -1}"
EOF2
  mock_bin xscreensaver-command <<'EOF2'
#!/bin/bash
[ "$1" = --version ] && exit 1
mock_log "xscreensaver-command $*"
EOF2
}

# run_set [VAR=value...] -- [args...]: stdin from $STDIN (empty by default).
run_set() {
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  OUTPUT=$(printf '%b' "${STDIN:-}" | env HOME="$H" DISPLAY=:0 XDG_SESSION_TYPE=x11 PATH="$(mock_path)" "${envs[@]}" \
    bash "$MOCK_DIR/ohmydebn-lock-screen-set" "$@" 2>&1)
  EXIT_CODE=$?
  # The daemon starter runs in the background.
  sleep 0.2
  CALLS=$(cat "$MOCK_CALLS")
}

# --- --current ---
setup
run_set -- --current
assert_eq "--current: empty setting is Cinnamon's" "cinnamon" "$OUTPUT"
printf '%s' "$LOCK_COMMAND" >"$MOCK_DIR/custom"
run_set -- --current
assert_eq "--current: OhMyDebn's lock command is XScreenSaver" "xscreensaver" "$OUTPUT"
printf '%s' "light-locker-command -l" >"$MOCK_DIR/custom"
run_set -- --current
assert_eq "--current: anything else is custom" "custom" "$OUTPUT"
mock_cleanup

# --- switching to XScreenSaver ---
setup
printf 'mode:\t\trandom\nlock:\t\tFalse\nfade:\t\tTrue\n' >"$H/.xscreensaver"
run_set -- xscreensaver --skip-prompt
assert_eq "to XScreenSaver: exits 0" "0" "$EXIT_CODE"
assert_contains "to XScreenSaver: installs it without asking again" "$CALLS" "ohmydebn-xscreensaver-install --skip-prompt"
assert_contains "to XScreenSaver: colors the dialog" "$CALLS" "ohmydebn-theme-set-xscreensaver"
assert_contains "to XScreenSaver: points Cinnamon at ohmydebn-lock" "$CALLS" "gsettings set org.cinnamon.desktop.screensaver custom-screensaver-command $LOCK_COMMAND"
assert_contains "to XScreenSaver: asks Cinnamon's screensaver to quit" "$CALLS" "gdbus org.cinnamon.ScreenSaver.Quit"
assert_contains "to XScreenSaver: starts the daemon now" "$CALLS" "ohmydebn-xscreensaver-start"
PREFS=$(cat "$H/.xscreensaver")
assert_contains "prefs: lock on" "$PREFS" "lock:		True"
assert_not_contains "prefs: the old lock line is replaced, not kept" "$PREFS" "lock:		False"
assert_contains "prefs: blank, no animations" "$PREFS" "mode:		blank"
assert_contains "prefs: locks as soon as it blanks" "$PREFS" "lockTimeout:		0:00:00"
assert_contains "prefs: display power saving left to Cinnamon" "$PREFS" "dpmsEnabled:		False"
assert_contains "prefs: other settings kept" "$PREFS" "fade:		True"
assert_eq "prefs: one lock line" "1" "$(grep -c '^lock:' "$H/.xscreensaver")"
assert_contains "autostart: starts at login in Cinnamon" "$(cat "$H/.config/autostart/ohmydebn-xscreensaver.desktop")" "Exec=/usr/share/ohmydebn/bin/ohmydebn-xscreensaver-start"
assert_contains "to XScreenSaver: says so" "$OUTPUT" "The lock screen is now XScreenSaver"

# --- and back, with no argument: switches to the one not in use ---
: >"$MOCK_CALLS"
run_set -- --skip-prompt
assert_eq "back: exits 0" "0" "$EXIT_CODE"
assert_contains "back: clears the setting" "$CALLS" "gsettings reset org.cinnamon.desktop.screensaver custom-screensaver-command"
assert_eq "back: no autostart" "no" "$([ -e "$H/.config/autostart/ohmydebn-xscreensaver.desktop" ] && echo yes || echo no)"
assert_contains "back: stops XScreenSaver" "$CALLS" "xscreensaver-command --exit"
assert_contains "back: starts Cinnamon's screensaver for idle locking" "$CALLS" "cinnamon-screensaver"
assert_contains "back: says so" "$OUTPUT" "The lock screen is now Cinnamon's"
mock_cleanup

# --- asks first; no answer, no change ---
setup
run_set -- xscreensaver
assert_eq "prompt, no answer: nothing set" "" "$(grep 'gsettings set' "$MOCK_CALLS")"
assert_contains "prompt: explains what's lost" "$OUTPUT" "without Cinnamon's media controls"
STDIN='\n' run_set -- xscreensaver
assert_contains "prompt, Enter: switches" "$CALLS" "gsettings set"
mock_cleanup

# --- a custom command someone else set: the prompt says it's replaced ---
setup
printf '%s' "light-locker-command -l" >"$MOCK_DIR/custom"
STDIN='\n' run_set -- xscreensaver
assert_contains "custom: prompt says it's replaced" "$OUTPUT" "It replaces the custom lock command"
assert_contains "custom: then switches" "$CALLS" "gsettings set org.cinnamon.desktop.screensaver custom-screensaver-command $LOCK_COMMAND"
mock_cleanup

# --- Wayland: refused, nothing changed ---
setup
run_set XDG_SESSION_TYPE=wayland -- xscreensaver --skip-prompt
assert_eq "wayland: exits 1" "1" "$EXIT_CODE"
assert_contains "wayland: says why" "$OUTPUT" "can't lock a Wayland session"
assert_eq "wayland: nothing installed or set" "" "$CALLS"
mock_cleanup

# --- already in use: nothing to do ---
setup
run_set -- cinnamon --skip-prompt
assert_eq "already Cinnamon's: exits 0" "0" "$EXIT_CODE"
assert_contains "already Cinnamon's: says so" "$OUTPUT" "already in use"
assert_eq "already Cinnamon's: nothing changed" "" "$CALLS"
mock_cleanup

# --- bad argument ---
setup
run_set -- bogus
assert_eq "bad argument: exits 1" "1" "$EXIT_CODE"
mock_cleanup

test_summary
