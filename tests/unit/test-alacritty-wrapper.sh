#!/bin/bash
#
# Unit tests for bin/ohmydebn-alacritty. In Cinnamon's Wayland session,
# Alacritty as a native Wayland window drew a plain grey title bar of its
# own (Cinnamon doesn't offer to draw it), while Nemo and Brave matched the
# OhMyDebn theme. Started as an X11 window through XWayland, it gets
# Cinnamon's themed title bar, and xdotool can find it again. The stand-in
# alacritty records its arguments, its WAYLAND_DISPLAY and its PID.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-alacritty ==="

setup() {
  mock_init
  mock_bin alacritty <<'STUB'
#!/bin/bash
echo "pid=$$" >"$MOCK_DIR/alacritty.out"
echo "wayland=${WAYLAND_DISPLAY-unset}" >>"$MOCK_DIR/alacritty.out"
for a in "$@"; do echo "arg=$a"; done >>"$MOCK_DIR/alacritty.out"
STUB
  sed "s#^ALACRITTY=/usr/bin/alacritty#ALACRITTY=$MOCK_BIN/alacritty#" "$REPO_ROOT/bin/ohmydebn-alacritty" >"$MOCK_DIR/wrapper"
}

# run <env assignments...> -- <args...>: runs the wrapper with only those
# display variables set; PID is the wrapper's own
run() {
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env -u WAYLAND_DISPLAY -u DISPLAY "${envs[@]}" PATH="$(mock_path)" bash "$MOCK_DIR/wrapper" "$@" </dev/null &
  PID=$!
  wait "$PID"
  OUT=$(cat "$MOCK_DIR/alacritty.out")
}

setup
run WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 -- --title "My shell" -e echo hi
assert_contains "Wayland: Alacritty itself has no WAYLAND_DISPLAY (an X11 window)" "$OUT" "wayland=unset"
assert_contains "Wayland: the terminal's own programs get it back" "$OUT" 'arg=env.WAYLAND_DISPLAY="wayland-0"'
assert_contains "Wayland: arguments pass through, spaces kept" "$OUT" "arg=My shell"
assert_contains "Wayland: -e and its command pass through" "$OUT" $'arg=-e\narg=echo\narg=hi'
assert_eq "Wayland: Alacritty keeps the wrapper's PID (callers look its window up by it)" "pid=$PID" "$(head -1 <<<"$OUT")"
mock_cleanup

setup
run DISPLAY=:0 -- --title Console
assert_contains "X11: started as it is" "$OUT" "wayland=unset"
assert_not_contains "X11: no env option added" "$OUT" "env.WAYLAND_DISPLAY"
assert_eq "X11: Alacritty keeps the wrapper's PID" "pid=$PID" "$(head -1 <<<"$OUT")"
mock_cleanup

setup
run WAYLAND_DISPLAY=wayland-0 -- --title Console
assert_contains "Wayland without XWayland (no DISPLAY): stays a Wayland window" "$OUT" "wayland=wayland-0"
assert_not_contains "Wayland without XWayland: no env option added" "$OUT" "env.WAYLAND_DISPLAY"
mock_cleanup

# Every OhMyDebn terminal starts through the wrapper, so none comes up
# with the grey Wayland title bar.
DIRECT=$(grep -rnE '/usr/bin/alacritty([^-_a-z]|$)|^[[:space:]]*alacritty ' "$REPO_ROOT/bin" | grep -v "^$REPO_ROOT/bin/ohmydebn-alacritty:" | grep -vE ':[0-9]+:[[:space:]]*#' || true)
assert_eq "no script starts alacritty except through ohmydebn-alacritty" "" "$DIRECT"

test_summary
