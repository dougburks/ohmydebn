#!/bin/bash
#
# Unit tests for bin/ohmydebn-xscreensaver-start, which starts XScreenSaver
# for the XScreenSaver lock screen after putting the unlock dialog's X
# resources in place. xrdb, gsettings, dm-tool and xscreensaver are mocks,
# and PATH is only the mocks plus bash, so whether dm-tool or xrdb exists
# is up to each test.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-xscreensaver-start"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-xscreensaver-start ==="

setup() {
  mock_init
  H="$MOCK_DIR/home"
  mkdir -p "$H/.config/ohmydebn/current" "$MOCK_DIR/tools"
  for t in bash cat; do ln -s "$(command -v "$t")" "$MOCK_DIR/tools/$t"; done
  # xrdb logs what it merged: a file's name, or what came on stdin.
  mock_bin xrdb <<'EOF2'
#!/bin/bash
if [ -n "${2:-}" ]; then mock_log "xrdb $*"; else mock_log "xrdb $* <<< $(cat)"; fi
EOF2
  mock_bin gsettings <<'EOF2'
#!/bin/bash
[ -n "${MOCK_GSETTINGS_FAILS:-}" ] && exit 1
[ "$*" = "get org.cinnamon.desktop.interface clock-use-24h" ] && echo "${MOCK_24H:-false}"
EOF2
  mock_bin dm-tool <<'EOF2'
#!/bin/bash
exit 0
EOF2
  mock_bin xscreensaver <<'EOF2'
#!/bin/bash
mock_log "xscreensaver $*"
EOF2
}

run_start() {
  OUTPUT=$(env HOME="$H" PATH="$MOCK_BIN:$MOCK_DIR/tools" "$@" bash "$SCRIPT" </dev/null 2>&1)
  EXIT_CODE=$?
  CALLS=$(cat "$MOCK_CALLS")
}

# --- the usual login: theme resources, a 12-hour date, New Login ---
setup
: >"$H/.config/ohmydebn/current/xscreensaver.Xresources"
run_start
assert_eq "login: exits 0" "0" "$EXIT_CODE"
assert_eq "login: prints nothing" "" "$OUTPUT"
assert_contains "login: merges the theme's colors and fonts" "$CALLS" "xrdb -merge $H/.config/ohmydebn/current/xscreensaver.Xresources"
assert_contains "login: 12-hour date, as Cinnamon's clock" "$CALLS" "XScreenSaver*dateFormat: %a %b %-d, %-I:%M %p"
assert_contains "login: New Login through LightDM" "$CALLS" "XScreenSaver.newLoginCommand: dm-tool switch-to-greeter"
assert_contains "login: starts XScreenSaver without its splash" "$CALLS" "xscreensaver --no-splash"
assert_eq "login: XScreenSaver starts last" "xscreensaver --no-splash" "$(tail -1 "$MOCK_CALLS")"
mock_cleanup

# --- Cinnamon's clock set to 24-hour ---
setup
run_start MOCK_24H=true
assert_contains "24-hour clock: 24-hour date" "$CALLS" "XScreenSaver*dateFormat: %a %b %-d, %H:%M"
assert_not_contains "24-hour clock: no AM/PM" "$CALLS" "%p"
mock_cleanup

# --- no theme resources yet, the clock setting unreadable ---
setup
run_start MOCK_GSETTINGS_FAILS=1
assert_not_contains "no resources file: nothing to merge from one" "$CALLS" "xrdb -merge $H"
assert_contains "no clock setting: 12-hour date" "$CALLS" "%-I:%M %p"
mock_cleanup

# --- no LightDM: no New Login button ---
setup
rm "$MOCK_BIN/dm-tool"
run_start
assert_not_contains "no dm-tool: no New Login command" "$CALLS" "newLoginCommand"
mock_cleanup

# --- no xrdb at all: XScreenSaver still starts, with its own look ---
setup
rm "$MOCK_BIN/xrdb"
run_start
assert_eq "no xrdb: exits 0" "0" "$EXIT_CODE"
assert_eq "no xrdb: only XScreenSaver ran" "xscreensaver --no-splash" "$CALLS"
mock_cleanup

test_summary
