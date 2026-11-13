#!/bin/bash
#
# Unit tests for bin/ohmydebn-keepass (Ctrl+Shift+K): start KeePassXC, or
# bring its window forward if it's already running. keepassxc-proxy keeps
# running while a browser uses the KeePassXC extension, and an unanchored
# `pgrep keepassxc` counted it as KeePassXC being open - so the key ran
# the window search, found no window, and nothing opened. pgrep is mocked
# to behave like the real one with only the proxy running.
#
# The window is brought forward through gTile (ohmydebn-gtile-windows),
# which sees it in Cinnamon's Wayland session; xdotool, which didn't, is
# only the fallback for when gTile doesn't answer.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-keepass ==="

# setup <running process names...>
setup() {
  mock_init
  printf '%s\n' "$@" >"$MOCK_DIR/processes"
  mock_bin pgrep <<'STUB'
#!/bin/bash
EXACT=false
[[ "$1" == "-x" ]] && EXACT=true && shift
while read -r P; do
  if [[ "$EXACT" == true && "$P" == "$1" ]] || [[ "$EXACT" == false && "$P" == *"$1"* ]]; then
    echo 4242
    exit 0
  fi
done <"$MOCK_DIR/processes"
exit 1
STUB
  mock_bin keepassxc <<'STUB'
#!/bin/bash
mock_log "keepassxc"
STUB
  mock_bin xdotool <<'STUB'
#!/bin/bash
mock_log "xdotool $*"
STUB
  mock_bin ohmydebn-gtile-windows <<'STUB'
#!/bin/bash
mock_log "gtile-windows $*"
exit "${MOCK_GTILE_EXIT:-0}"
STUB
  sed -e "s#/usr/bin/keepassxc#$MOCK_BIN/keepassxc#; s#/usr/bin/xdotool#$MOCK_BIN/xdotool#" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-windows#$MOCK_BIN/ohmydebn-gtile-windows#" \
    "$REPO_ROOT/bin/ohmydebn-keepass" >"$MOCK_DIR/keepass"
}

run() {
  PATH="$(mock_path)" bash "$MOCK_DIR/keepass" </dev/null >"$MOCK_DIR/out" 2>&1
  wait
  sleep 0.1
}

setup keepassxc-proxy
run
assert_eq "only the browser proxy running: starts KeePassXC" "keepassxc" "$(cat "$MOCK_CALLS")"
mock_cleanup

setup keepassxc keepassxc-proxy
run
assert_eq "KeePassXC running: gTile brings its window forward" "gtile-windows activate-class keepassxc" "$(cat "$MOCK_CALLS")"
assert_eq "KeePassXC running: prints no PIDs" "" "$(cat "$MOCK_DIR/out")"
mock_cleanup

setup keepassxc
MOCK_GTILE_EXIT=1 run
assert_contains "gTile not answering: falls back to xdotool" "$(cat "$MOCK_CALLS")" "xdotool search --name .*- KeePassXC windowactivate"
assert_not_contains "gTile not answering: doesn't start a second KeePassXC" "$(cat "$MOCK_CALLS")" $'\nkeepassxc'
mock_cleanup

setup
run
assert_eq "nothing running: starts KeePassXC" "keepassxc" "$(cat "$MOCK_CALLS")"
mock_cleanup

test_summary
