#!/bin/bash
#
# Unit tests for bin/ohmydebn-fastfetch-logo-generate: the still logo
# (config/fastfetch/logo.txt in the theme's logo gradient, written to
# ~/.config/fastfetch/ohmydebn-logo.txt) and the animation frames the
# system summary window plays (~/.cache/ohmydebn/fastfetch-logo-frames).
# The real ohmydebn-theme-logo-colors supplies the gradient. The color
# checks use a small fixture logo whose corners are drawn, so its first
# cell is exactly the gradient's start, its last exactly the end, and its
# top-right corner exactly halfway.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-fastfetch-logo-generate"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-fastfetch-logo-generate ==="

mock_init
sed -e "s#/usr/share/ohmydebn/bin#$REPO_ROOT/bin#g" \
  -e "s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" "$SCRIPT" >"$MOCK_DIR/gen.py"
printf '█  █\n▀  ▄\n' >"$MOCK_DIR/logo.txt"
printf '█  █\n█  █\n' >"$MOCK_DIR/logo-wink.txt"
sed -e "s#^LOGO_SOURCE = .*#LOGO_SOURCE = \"$MOCK_DIR/logo.txt\"#" \
  -e "s#^WINK_SOURCE = .*#WINK_SOURCE = \"$MOCK_DIR/logo-wink.txt\"#" "$MOCK_DIR/gen.py" >"$MOCK_DIR/gen-fixture.py"
LOGO_SOURCE="$REPO_ROOT/config/fastfetch/logo.txt"
WINK_SOURCE="$REPO_ROOT/config/fastfetch/logo-wink.txt"

new_home() {
  SCRATCH_HOME=$(mktemp -d)
  LOGO="$SCRATCH_HOME/.config/fastfetch/ohmydebn-logo.txt"
  FRAMES="$SCRATCH_HOME/.cache/ohmydebn/fastfetch-logo-frames"
}
run_gen() {
  HOME="$SCRATCH_HOME" python3 "$MOCK_DIR/${1:-gen}.py" </dev/null >"$MOCK_DIR/out" 2>&1
}
write_theme() { # accent blue cyan [mode]
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current/theme"
  printf 'mode = "%s"\naccent = "#%s"\nbackground = "#1a1b26"\nblue = "#%s"\ncyan = "#%s"\n' \
    "${4:-dark}" "$1" "$2" "$3" >"$SCRATCH_HOME/.config/ohmydebn/current/theme/colors.toml"
}
strip_colors() {
  sed $'s/\e\\[[0-9;]*m//g'
}
# A file with every escape character shown as ESC.
show_escapes() {
  sed $'s/\e/ESC/g' "$1"
}
# frame <n>: frame n of the frames file, one logo row per line, without
# the cursor moves and line-wrap switches around them.
frame() {
  python3 -I -c '
import re, sys
f = open(sys.argv[1], encoding="utf-8").read().split("\0")[int(sys.argv[2])]
f = f.replace("\x1b[?7l", "").replace("\x1b[?7h", "")
print("\n".join(re.split(r"\x1b\[\d+;1H", f)[1:]))' "$FRAMES" "$1"
}
frame_count() {
  python3 -I -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read().split("\0")))' "$FRAMES"
}

# Scenario 1: a theme, with the real logo - it keeps its exact shape,
# each line ends with a color reset, and the files are readable by all.
new_home
write_theme 7aa2f7 7aa2f7 449dab
run_gen
assert_eq "theme: succeeds" "0" "$?"
assert_eq "theme: the logo keeps its shape" "$(cat "$LOGO_SOURCE")" "$(strip_colors <"$LOGO")"
assert_eq "theme: every line ends with a color reset" "$(wc -l <"$LOGO_SOURCE")" \
  "$(grep -c $'\e\\[0m$' "$LOGO")"
assert_eq "theme: logo is world-readable, not writable" "644" "$(stat -c %a "$LOGO")"
assert_eq "theme: frames are world-readable, not writable" "644" "$(stat -c %a "$FRAMES")"

# Scenario 2: the frames - 22 of the shimmer (1.1 seconds at 20 a
# second), then the still logo, then the wink, each one the same rows as
# the logo, drawn from the top-left corner with line wrap off.
assert_eq "frames: 22 shimmer + still + wink" "24" "$(frame_count)"
assert_eq "frames: the still frame is the logo itself" "$(cat "$LOGO")" "$(frame 22)"
assert_eq "frames: the wink frame is the winking shape" "$(cat "$WINK_SOURCE")" "$(frame 23 | strip_colors)"
assert_eq "frames: the shimmer keeps the logo's shape" "$(cat "$LOGO_SOURCE")" "$(frame 11 | strip_colors)"
assert_eq "frames: the shimmer starts off the face (first frame unchanged)" "$(cat "$LOGO")" "$(frame 0)"
assert_contains "frames: each starts at the top-left with wrap off" \
  "$(head -c 12 "$FRAMES" | show_escapes /dev/stdin)" "ESC[?7lESC[1;1H"

# Scenario 3: run again with nothing changed - neither file is rewritten.
touch -d '2020-01-01' "$LOGO" "$FRAMES"
BEFORE_LOGO=$(stat -c %Y "$LOGO")
BEFORE_FRAMES=$(stat -c %Y "$FRAMES")
run_gen
assert_eq "unchanged colors: logo not rewritten" "$BEFORE_LOGO" "$(stat -c %Y "$LOGO")"
assert_eq "unchanged colors: frames not rewritten" "$BEFORE_FRAMES" "$(stat -c %Y "$FRAMES")"
rm -rf "$SCRATCH_HOME"

# Scenario 4: the gradient runs from the accent (top left) to cyan
# (bottom right), corner to corner, and blank cells get no color.
new_home
write_theme 7aa2f7 7aa2f7 449dab
run_gen gen-fixture
assert_eq "gradient: accent to cyan, corner to corner" \
  "ESC[38;2;122;162;247m█  ESC[38;2;95;160;209m█ESC[0m
ESC[38;2;95;160;209m▀  ESC[38;2;68;157;171m▄ESC[0m" "$(show_escapes "$LOGO")"

# Scenario 5: halfway through the shimmer (frame 11) the band is centered
# on the diagonal's middle, lifting the top-right and bottom-left cells
# three quarters of the way to white on a dark theme, and the corners
# not at all.
assert_eq "shimmer: halfway, the middle lifted toward white" \
  "ESC[38;2;122;162;247m█  ESC[38;2;215;231;244m█ESC[0m
ESC[38;2;215;231;244m▀  ESC[38;2;68;157;171m▄ESC[0m" "$(frame 11 | show_escapes /dev/stdin)"

# Scenario 6: a theme change recolors both, leaving no temporary files;
# on a light theme the band lifts colors a little less (60%).
write_theme d14d41 205ea6 3aa99f light
run_gen gen-fixture
assert_eq "new theme: recolored, accent to cyan via blue" \
  "ESC[38;2;209;77;65m█  ESC[38;2;32;94;166m█ESC[0m
ESC[38;2;32;94;166m▀  ESC[38;2;58;169;159m▄ESC[0m" "$(show_escapes "$LOGO")"
assert_contains "light theme: the band lifts the middle 60% toward white" \
  "$(frame 11 | show_escapes /dev/stdin)" "ESC[38;2;166;191;219m█"
ls -A "$SCRATCH_HOME/.config/fastfetch" "$SCRATCH_HOME/.cache/ohmydebn" >"$MOCK_DIR/ls"
assert_not_contains "no temporary files left behind" "$(cat "$MOCK_DIR/ls")" ".ohmydebn-logo.txt."
assert_not_contains "no temporary frames left behind" "$(cat "$MOCK_DIR/ls")" ".fastfetch-logo-frames."
rm -rf "$SCRATCH_HOME"

# Scenario 7: no theme at all - the default palette (488bff b2e7de 57eaf7).
new_home
run_gen gen-fixture
assert_eq "no theme: succeeds" "0" "$?"
assert_eq "no theme: the default palette" \
  "ESC[38;2;72;139;255m█  ESC[38;2;178;231;222m█ESC[0m
ESC[38;2;178;231;222m▀  ESC[38;2;87;234;247m▄ESC[0m" "$(show_escapes "$LOGO")"
rm -rf "$SCRATCH_HOME"

# Scenario 8: no logo shape installed - nothing written, no error.
new_home
sed "s#^LOGO_SOURCE = .*#LOGO_SOURCE = \"$MOCK_DIR/missing.txt\"#" "$MOCK_DIR/gen.py" >"$MOCK_DIR/gen-missing.py"
run_gen gen-missing
assert_eq "no shape: succeeds" "0" "$?"
assert_eq "no shape: nothing written" "no" "$([ -e "$LOGO" ] || [ -e "$FRAMES" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"

# Scenario 9: the shape files. Both fastfetch configs point at the colored
# logo, printed as-is; the logo fits beside fastfetch's info lines (18
# rows, at most 36 columns); and the wink is the same size, differing only
# where the right eye is (rows 6-8).
for config in config.jsonc.tpl config-default.jsonc; do
  assert_contains "$config: raw logo from the colored copy" \
    "$(tr -d ' \n' <"$REPO_ROOT/config/fastfetch/$config")" \
    '"logo":{"type":"file-raw","source":"~/.config/fastfetch/ohmydebn-logo.txt"}'
done
assert_eq "logo.txt: 18 rows" "18" "$(wc -l <"$LOGO_SOURCE")"
assert_eq "logo.txt: at most 36 columns" "yes" "$(LC_ALL=C.UTF-8 bash -c '
  w=0; while IFS= read -r l; do [ ${#l} -gt $w ] && w=${#l}; done <"$1"; [ $w -le 36 ] && [ $w -gt 30 ] && echo yes' _ "$LOGO_SOURCE")"
assert_eq "logo-wink.txt: differs only in rows 6-8" "6,8c6,8" \
  "$(diff "$LOGO_SOURCE" "$WINK_SOURCE" | grep -v '^[<>-]')"
mock_cleanup

test_summary
