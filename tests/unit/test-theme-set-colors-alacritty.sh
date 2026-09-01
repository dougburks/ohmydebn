#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-colors's "alacritty.toml-derived"
# branch - used when a theme (most commonly one installed from a git repo
# via ohmydebn-theme-install, since that path denies the theme's own
# alacritty.toml but still resolves colors from the original, unfiltered
# source directory) ships an alacritty.toml instead of a colors.toml.
#
# Regression test #1: this branch used to only ever derive color0/7/8/15
# (black/white, normal+bright) and silently left color1-6 and color9-14
# (red/green/yellow/blue/magenta/cyan, normal+bright) out of the generated
# colors file entirely. ohmydebn-theme-set-templates only emits a sed
# substitution for a {{ colorN }} placeholder when that key actually appears
# in the colors file it read - so all 12 missing keys were left as literal
# "{{ color12 }}" etc. in the rendered alacritty.toml, which Alacritty then
# refused to parse as a color ("Config error: ... failed to parse rgb color
# {{ color12 }}").
#
# Regression test #2: even after deriving all 16 keys, a bare `red = "..."`
# line looks identical whether it's under [colors.normal] or [colors.bright]
# - naively grepping the whole file for "red" can't tell the two apart and
# always returns whichever occurs first (the normal one), so every bright.*
# color silently resolved to its normal.* counterpart instead of the theme's
# actual bright palette, for the (very common) section-header TOML style.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-colors"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-colors (alacritty.toml-derived) ==="

get_key() {
  # Usage: get_key <colors-file> <key>
  grep -E "^\s*$2\s*=" "$1" | tail -1 | sed -E 's/.*=\s*"([^"]*)".*/\1/'
}

SCRATCH=$(mktemp -d)

# --- Section-header style, normal and bright deliberately distinct - proves
# bright.* is read from [colors.bright], not just "first match in the file" ---
THEME="$SCRATCH/theme"
mkdir -p "$THEME"
cat >"$THEME/alacritty.toml" <<'TOML'
[colors.primary]
background = "#1a1b26"
foreground = "#a9b1d6"

[colors.cursor]
cursor = "#c0caf5"

[colors.normal]
black = "#15161e"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#bb9af7"
cyan = "#7dcfff"
white = "#a9b1d6"

[colors.bright]
black = "#414868"
red = "#ff5370"
green = "#c3e88d"
yellow = "#ffcb6b"
blue = "#82aaff"
magenta = "#c792ea"
cyan = "#89ddff"
white = "#c0caf5"
TOML

OUTPUT_PATH=$(bash "$SCRIPT" "$THEME")
assert_eq "prints a temp file path" "yes" "$([[ -f $OUTPUT_PATH ]] && echo yes || echo no)"

declare -A EXPECT=(
  [color0]="#15161e" [color1]="#f7768e" [color2]="#9ece6a" [color3]="#e0af68"
  [color4]="#7aa2f7" [color5]="#bb9af7" [color6]="#7dcfff" [color7]="#a9b1d6"
  [color8]="#414868" [color9]="#ff5370" [color10]="#c3e88d" [color11]="#ffcb6b"
  [color12]="#82aaff" [color13]="#c792ea" [color14]="#89ddff" [color15]="#c0caf5"
)
for key in "${!EXPECT[@]}"; do
  assert_eq "$key resolves to its own section's color, not the other section's" "${EXPECT[$key]}" "$(get_key "$OUTPUT_PATH" "$key")"
done

rm -f "$OUTPUT_PATH"

# --- A theme with only [colors.normal] (no [colors.bright] section at all) ---
# should fall each bright color back to its normal-variant, not to foreground.
THEME2="$SCRATCH/theme-no-bright"
mkdir -p "$THEME2"
cat >"$THEME2/alacritty.toml" <<'TOML'
[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[colors.normal]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#bac2de"
TOML

OUTPUT_PATH2=$(bash "$SCRIPT" "$THEME2")
assert_eq "color9 (bright red) falls back to normal red, not foreground" "#f38ba8" "$(get_key "$OUTPUT_PATH2" "color9")"
assert_eq "color12 (bright blue) falls back to normal blue, not foreground" "#89b4fa" "$(get_key "$OUTPUT_PATH2" "color12")"
assert_eq "color8 (bright black) falls back to normal black, not foreground" "#45475a" "$(get_key "$OUTPUT_PATH2" "color8")"

rm -f "$OUTPUT_PATH2"

# --- Dotted-key style (no table headers at all) - the other syntax real
# themes use, still needs to resolve correctly by section. ---
THEME3="$SCRATCH/theme-dotted"
mkdir -p "$THEME3"
cat >"$THEME3/alacritty.toml" <<'TOML'
colors.primary.background = "#000000"
colors.primary.foreground = "#ffffff"
colors.normal.red = "#aa0000"
colors.bright.red = "#ff0000"
TOML

OUTPUT_PATH3=$(bash "$SCRIPT" "$THEME3")
assert_eq "dotted-key style: color1 (normal red)" "#aa0000" "$(get_key "$OUTPUT_PATH3" "color1")"
assert_eq "dotted-key style: color9 (bright red)" "#ff0000" "$(get_key "$OUTPUT_PATH3" "color9")"

rm -f "$OUTPUT_PATH3"
rm -rf "$SCRATCH"

test_summary
