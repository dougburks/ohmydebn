#!/bin/bash
#
# Unit tests for bin/ohmydebn-screenshot, the OhMyDebn menu's Screenshot
# entries. They pressed Cinnamon's Print keys with xdotool, which in
# Cinnamon's Wayland session only reaches X11 windows, never Cinnamon:
# Region, Window and Display did nothing (Linux Mint 27). xdotool, gdbus
# and xdg-user-dir are stand-ins that log, so nothing is captured.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-screenshot ==="

setup() {
  mock_init
  printf '#!/bin/bash\nmock_log "xdotool $*"\n' | mock_bin xdotool
  mock_bin gdbus <<'EOF'
#!/bin/bash
mock_log "gdbus $*"
case "$*" in
  *SelectWindow*)
    [ -n "${MOCK_SELECT_FAILS:-}" ] && { echo "Error: cancelled" >&2; exit 1; }
    echo "(uint64 1429488226,)" ;;
  *ScreenshotWindowById*) echo "(true, 'saved')" ;;
  *HandleKeybinding*) echo "()" ;;
esac
EOF
  mkdir -p "$MOCK_DIR/home/Pictures"
  printf '#!/bin/bash\necho "%s"\n' "$MOCK_DIR/home/Pictures" | mock_bin xdg-user-dir
  sed -e "s#/usr/bin/xdotool#$MOCK_BIN/xdotool#g; s#/usr/bin/gdbus#$MOCK_BIN/gdbus#g" \
    -e "s#/usr/bin/xdg-user-dir#$MOCK_BIN/xdg-user-dir#g" \
    "$REPO_ROOT/bin/ohmydebn-screenshot" >"$MOCK_DIR/screenshot"
}

# shot <x11|wayland> <kind>: CALLS holds what it did, STATUS its exit code.
shot() {
  local wayland=""
  [ "$1" = wayland ] && wayland="wayland-0"
  HOME="$MOCK_DIR/home" PATH="$(mock_path)" XDG_SESSION_TYPE="$1" WAYLAND_DISPLAY="$wayland" \
    bash "$MOCK_DIR/screenshot" "$2" </dev/null >/dev/null 2>&1
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

HANDLER="gdbus call --session --dest org.cinnamon.SettingsDaemon.KeybindingHandler --object-path /org/cinnamon/SettingsDaemon/KeybindingHandler --method org.cinnamon.SettingsDaemon.KeybindingHandler.HandleKeybinding"

# X11: Cinnamon's own Print keys, as before.
for pair in "region:Shift+Print" "window:Alt+Print" "display:Print"; do
  setup
  shot x11 "${pair%%:*}"
  assert_contains "X11, ${pair%%:*}: presses ${pair#*:}" "$CALLS" "xdotool key ${pair#*:}"
  assert_not_contains "X11, ${pair%%:*}: no D-Bus" "$CALLS" "gdbus"
  mock_cleanup
done

# Wayland: Region and Display through the settings daemon.
setup
shot wayland region
assert_eq "Wayland, region: succeeds" "0" "$STATUS"
assert_contains "Wayland, region: the area screenshot action (23)" "$CALLS" "$HANDLER 23"
assert_not_contains "Wayland, region: no xdotool" "$CALLS" "xdotool"
mock_cleanup

setup
shot wayland display
assert_contains "Wayland, display: the screenshot action (18)" "$CALLS" "$HANDLER 18"
assert_not_contains "Wayland, display: no xdotool" "$CALLS" "xdotool"
mock_cleanup

# Wayland: Window picks a window, then saves it, title bar included.
setup
shot wayland window
assert_eq "Wayland, window: succeeds" "0" "$STATUS"
assert_contains "Wayland, window: asks which window" "$CALLS" "org.cinnamon.Screenshot.SelectWindow"
assert_contains "Wayland, window: captures that one, with its frame, into Pictures" "$CALLS" \
  "org.cinnamon.Screenshot.ScreenshotWindowById 1429488226 true false $MOCK_DIR/home/Pictures/Screenshot "
assert_eq "Wayland, window: named like Cinnamon's own (Screenshot 2026-11-12 18-21-49.268.png)" "yes" \
  "$(grep -qP 'Pictures/Screenshot \d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2}\.\d{3}\.png false' <<<"$CALLS" && echo yes || echo no)"
assert_not_contains "Wayland, window: no xdotool" "$CALLS" "xdotool"
mock_cleanup

setup
MOCK_SELECT_FAILS=1 shot wayland window
assert_eq "Wayland, window cancelled (Escape): exits quietly" "0" "$STATUS"
assert_not_contains "Wayland, window cancelled: nothing captured" "$CALLS" "ScreenshotWindowById"
mock_cleanup

setup
shot x11 everything
assert_eq "an unknown kind: usage error" "1" "$STATUS"
assert_not_contains "an unknown kind: nothing pressed" "$CALLS" "xdotool"
mock_cleanup

test_summary
