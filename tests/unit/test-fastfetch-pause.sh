#!/bin/bash
#
# Unit tests for bin/ohmydebn-fastfetch-pause's own pidfile lifecycle and
# SIGUSR2 re-render trap, added alongside ohmydebn-theme-set-fastfetch's new
# refresh-in-place behavior. test-theme-set-fastfetch.sh already covers the
# sending side (against a fake stand-in process) - these exercise the real
# script itself: does it actually write its PID where the sender expects,
# does SIGUSR2 actually trigger a second render, and is the pidfile cleaned
# up on exit so a later sender's /proc/*/cmdline guard doesn't need to.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-fastfetch-pause"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-fastfetch-pause ==="

mock_init
mock_bin ohmydebn-fastfetch <<'EOF'
#!/bin/bash
mock_log "rendered"
EOF
sed -e "s#/usr/share/ohmydebn/bin/ohmydebn-fastfetch#$MOCK_BIN/ohmydebn-fastfetch#" \
  "$SCRIPT" >"$MOCK_DIR/fastfetch-pause-patched.sh"

SCRATCH_HOME=$(mktemp -d)
PID_FILE="$SCRATCH_HOME/.cache/ohmydebn/fastfetch-pause.pid"
# A terminal stand-in for the windows' input: a FIFO held open and never
# written, so their key reads time out as they do at a real terminal (the
# script ends at end-of-input).
mkfifo "$MOCK_DIR/tty"
exec 3<>"$MOCK_DIR/tty"
HOME="$SCRATCH_HOME" bash "$MOCK_DIR/fastfetch-pause-patched.sh" <&3 >/dev/null 2>&1 &
WRAPPER_PID=$!
sleep 0.3

assert_eq "pidfile holds this process's own PID" "$WRAPPER_PID" "$(cat "$PID_FILE" 2>/dev/null)"
assert_contains "renders once on start" "$(cat "$MOCK_CALLS")" "rendered"

kill -SIGUSR2 "$WRAPPER_PID"
sleep 0.3
assert_eq "SIGUSR2 triggers a second render" "2" "$(grep -c rendered "$MOCK_CALLS")"

kill "$WRAPPER_PID" 2>/dev/null
wait "$WRAPPER_PID" 2>/dev/null
sleep 0.2
PID_FILE_STATE="gone"
[ -f "$PID_FILE" ] && PID_FILE_STATE="still present"
assert_eq "pidfile removed on exit" "gone" "$PID_FILE_STATE"

# Two windows: the second's PID is in the file, and the first closing
# must leave it, or a theme change no longer refreshes the one still open.
HOME="$SCRATCH_HOME" bash "$MOCK_DIR/fastfetch-pause-patched.sh" <&3 >/dev/null 2>&1 &
FIRST_PID=$!
sleep 0.3
HOME="$SCRATCH_HOME" bash "$MOCK_DIR/fastfetch-pause-patched.sh" <&3 >/dev/null 2>&1 &
SECOND_PID=$!
sleep 0.3
kill "$FIRST_PID" 2>/dev/null
wait "$FIRST_PID" 2>/dev/null
sleep 0.2
assert_eq "two windows: closing the first keeps the second's pidfile" "$SECOND_PID" "$(cat "$PID_FILE" 2>/dev/null)"
kill "$SECOND_PID" 2>/dev/null
wait "$SECOND_PID" 2>/dev/null

# End of input closes the window, rather than spinning on it.
HOME="$SCRATCH_HOME" timeout 5 bash "$MOCK_DIR/fastfetch-pause-patched.sh" </dev/null >/dev/null 2>&1
assert_eq "end of input closes the window" "0" "$?"

exec 3<&-
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- The logo animation. It needs a real terminal, so these run the
# script inside `script`'s pseudo-terminal, set to 40 rows. Nothing
# answers the script's cursor-position question there, so the test types
# the answer itself: "\e[<row>;1R" (row 3: fastfetch's output fit, so the
# logo is still at the top). The frames are markers - F0..F21 for the
# shimmer, STILL, WINK - so the output shows which were drawn, in order.
mock_init
mock_bin ohmydebn-fastfetch <<'EOF'
#!/bin/bash
echo "fastfetch output"
EOF
mock_bin ohmydebn-fastfetch-logo-generate <<'EOF'
#!/bin/bash
mock_log "generated"
EOF
mock_bin gsettings <<'EOF'
#!/bin/bash
case "$3" in
desktop-effects-workspace) echo "${MOCK_EFFECTS:-true}" ;;
enable-animations) echo "${MOCK_ANIMATIONS:-true}" ;;
esac
EOF
sed -e "s#/usr/share/ohmydebn/bin/ohmydebn-fastfetch-logo-generate#$MOCK_BIN/ohmydebn-fastfetch-logo-generate#" \
  -e "s#/usr/share/ohmydebn/bin/ohmydebn-fastfetch\$#$MOCK_BIN/ohmydebn-fastfetch#" \
  "$SCRIPT" >"$MOCK_DIR/fastfetch-pause-patched.sh"

anim_home() {
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.config/fastfetch" "$SCRATCH_HOME/.cache/ohmydebn"
  echo '{ "logo": { "type": "file-raw", "source": "~/.config/fastfetch/ohmydebn-logo.txt" } }' \
    >"$SCRATCH_HOME/.config/fastfetch/config.jsonc"
  for i in $(seq 0 21); do printf 'F%s\0' "$i"; done >"$SCRATCH_HOME/.cache/ohmydebn/fastfetch-logo-frames"
  printf 'STILL\0WINK' >>"$SCRATCH_HOME/.cache/ohmydebn/fastfetch-logo-frames"
}

# run_window <seconds> <cursor row answer>: the window for that long, in a
# 40-row terminal; its output (escapes shown as ESC) lands in $MOCK_DIR/screen.
run_window() {
  { sleep 0.4; printf '\e[%s;1R' "$2"; sleep "$1"; } |
    HOME="$SCRATCH_HOME" PATH="$(mock_path)" timeout 10 \
      script -qec "stty rows 40 cols 120; bash $MOCK_DIR/fastfetch-pause-patched.sh" /dev/null 2>&1 |
    sed $'s/\e/ESC/g' >"$MOCK_DIR/screen"
}
# The frames drawn, in order, one per line.
drawn() {
  sed -e 's/ESC7/\nESC7/g' -e 's/ESC8/\n/g' "$MOCK_DIR/screen" | sed -n 's/^ESC7//p'
}

# Scenario A: the shimmer plays straight away, frame by frame, then the
# still logo goes back.
anim_home
run_window 1.6 3
assert_eq "shimmer: all its frames, in order, then the still logo" \
  "$(printf 'F%s\n' $(seq 0 21); echo STILL)" "$(drawn | head -23)"
assert_contains "frames drawn with the cursor saved and put back" "$(cat "$MOCK_DIR/screen")" "ESC7F0ESC8"
rm -rf "$SCRATCH_HOME"

# Scenario B: a little over two seconds in, the wink, and then the still
# logo again.
anim_home
run_window 3 3
assert_eq "wink: after the shimmer, then the still logo again" "STILL
WINK
STILL" "$(drawn | sed -n '23,25p')"
rm -rf "$SCRATCH_HOME"

# Scenario C: animations turned off in Cinnamon - nothing is drawn.
anim_home
MOCK_EFFECTS=false run_window 1 3
assert_eq "desktop effects off: no animation" "" "$(drawn)"
MOCK_ANIMATIONS=false run_window 1 3
assert_eq "animations off (accessibility): no animation" "" "$(drawn)"
rm -rf "$SCRATCH_HOME"

# Scenario D: fastfetch's output filled the screen (the cursor ended on
# the last row), so it may have scrolled and the logo isn't at the top.
anim_home
run_window 1 40
assert_eq "output reached the bottom: no animation" "" "$(drawn)"
rm -rf "$SCRATCH_HOME"

# Scenario E: fastfetch isn't showing OhMyDebn's logo (a theme's own
# config chose another) - nothing is drawn over it.
anim_home
echo '{ "logo": { "source": "debian" } }' >"$SCRATCH_HOME/.config/fastfetch/config.jsonc"
run_window 1 3
assert_eq "another logo: no animation" "" "$(drawn)"
rm -rf "$SCRATCH_HOME"

# Scenario F: the frames are missing (a cleared cache) - the window makes
# them, then plays them.
anim_home
mv "$SCRATCH_HOME/.cache/ohmydebn/fastfetch-logo-frames" "$MOCK_DIR/frames"
cat >"$MOCK_BIN/ohmydebn-fastfetch-logo-generate" <<EOF
#!/bin/bash
cp "$MOCK_DIR/frames" "\$HOME/.cache/ohmydebn/fastfetch-logo-frames"
EOF
run_window 1 3
assert_eq "missing frames: made, then played" "F0" "$(drawn | head -1)"
rm -rf "$SCRATCH_HOME"

# Scenario G: a theme change (SIGUSR2) while the window is open redraws
# it and the animation starts over. It used to stop: the redraw ran
# inside the signal handler, where asking the cursor position failed.
anim_home
PID_FILE="$SCRATCH_HOME/.cache/ohmydebn/fastfetch-pause.pid"
{ sleep 0.4; printf '\e[3;1R'; sleep 1.4; kill -USR2 "$(cat "$PID_FILE")"; sleep 0.3; printf '\e[3;1R'; sleep 1.5; } |
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" timeout 10 \
    script -qec "stty rows 40 cols 120; bash $MOCK_DIR/fastfetch-pause-patched.sh" /dev/null 2>&1 |
  sed $'s/\e/ESC/g' >"$MOCK_DIR/screen"
assert_eq "theme change: redrawn" "2" "$(grep -o 'fastfetch output' "$MOCK_DIR/screen" | wc -l)"
assert_eq "theme change: the shimmer plays again after the redraw" \
  "$(printf 'F%s\n' $(seq 0 21); echo STILL; printf 'F%s\n' $(seq 0 21); echo STILL)" "$(drawn | head -46)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
