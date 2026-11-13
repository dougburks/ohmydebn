#!/bin/bash
#
# Unit tests for bin/ohmydebn-cinnamon-recorder, the OhMyDebn menu's
# Cinnamon Recorder Start/Stop. It pressed the recorder's hotkey
# (Shift+Ctrl+Alt+R) with xdotool, which in Cinnamon's Wayland session only
# reaches X11 windows, never Cinnamon: the entry did nothing (Linux Mint
# 27). gTile's ToggleRecording does it from inside Cinnamon. gdbus, xdotool
# and notify-send are stand-ins that log, so nothing is recorded.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-cinnamon-recorder ==="

setup() {
  mock_init
  mock_bin gdbus <<'EOF'
#!/bin/bash
mock_log "gdbus $*"
[ -n "${MOCK_GTILE_FAILS:-}" ] && { echo "Error: org.freedesktop.DBus.Error.UnknownMethod" >&2; exit 1; }
echo "(true,)"
EOF
  printf '#!/bin/bash\nmock_log "xdotool $*"\n' | mock_bin xdotool
  printf '#!/bin/bash\nmock_log "notify-send $*"\n' | mock_bin notify-send
  sed -e "s#/usr/bin/gdbus#$MOCK_BIN/gdbus#g; s#/usr/bin/xdotool#$MOCK_BIN/xdotool#g" \
    "$REPO_ROOT/bin/ohmydebn-cinnamon-recorder" >"$MOCK_DIR/recorder"
}

# toggle <x11|wayland>: CALLS holds what it did, STATUS its exit code.
toggle() {
  local wayland=""
  [ "$1" = wayland ] && wayland="wayland-0"
  PATH="$(mock_path)" XDG_SESSION_TYPE="$1" WAYLAND_DISPLAY="$wayland" \
    bash "$MOCK_DIR/recorder" </dev/null >/dev/null 2>&1
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

TOGGLE="gdbus call --session --dest org.gTile.Control --object-path /org/gTile/Control --method org.gTile.Control.ToggleRecording"

for session in wayland x11; do
  setup
  toggle "$session"
  assert_eq "$session: succeeds" "0" "$STATUS"
  assert_contains "$session: gTile toggles the recorder" "$CALLS" "$TOGGLE"
  assert_not_contains "$session: no xdotool" "$CALLS" "xdotool"
  mock_cleanup
done

# gTile not answering (disabled, or older than ToggleRecording).
setup
MOCK_GTILE_FAILS=1 toggle x11
assert_eq "X11, gTile not answering: succeeds" "0" "$STATUS"
assert_contains "X11, gTile not answering: presses the hotkey, as before" "$CALLS" "xdotool key Shift+Ctrl+Alt+R"
mock_cleanup

setup
MOCK_GTILE_FAILS=1 toggle wayland
assert_eq "Wayland, gTile not answering: fails" "1" "$STATUS"
assert_not_contains "Wayland, gTile not answering: no xdotool (it wouldn't reach Cinnamon)" "$CALLS" "xdotool"
assert_contains "Wayland, gTile not answering: says to press the hotkey" "$CALLS" "Press Shift + Ctrl + Alt + R"
mock_cleanup

test_summary
