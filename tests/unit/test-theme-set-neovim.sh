#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-neovim, which gives a theme with no
# neovim.lua of its own one generated from its colors.toml (the aether
# colorscheme, as Omarchy does it) - so Neovim matches every theme, not only
# the ones that ship a neovim.lua. Its output is Lua that Neovim runs at
# startup, built from a colors.toml that may come from a theme installed
# from anywhere, so the hostile-input cases matter as much as the colors.
# The template comes from this repo; themes are scratch directories.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-neovim ==="

mock_init
sed "s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" "$REPO_ROOT/bin/ohmydebn-theme-set-neovim" >"$MOCK_BIN/gen"
chmod +x "$MOCK_BIN/gen"

# theme <name> <colors.toml content>: a scratch theme directory
theme() {
  local dir="$MOCK_DIR/$1"
  mkdir -p "$dir"
  printf '%s\n' "$2" >"$dir/colors.toml"
  echo "$dir"
}
gen() { bash "$MOCK_BIN/gen" "$1" 2>"$MOCK_DIR/stderr"; }
color() { sed -n "s/^ *$2 = \"\\(.*\\)\",$/\\1/p" "$1/neovim.lua"; }

# --- an Omarchy 4 theme (semantic colors): every color taken from it ---
T=$(theme semantic 'background = "#060B1E"
dark_background = "#040816"
darker_background = "#030610"
lighter_background = "#131a3a"
foreground = "#ffcead"
dark_foreground = "#6d7db6"
light_foreground = "#c9b8a6"
bright_foreground = "#ffcead"
muted = "#6d7db6"
accent = "#7d82d9"
selection = "#252e56"
selection_foreground = "#ffcead"
selection_background = "#252e56"
red = "#ED5B5A"
yellow = "#E9BB4F"
orange = "#eb8b54"
green = "#92a593"
cyan = "#a3bfd1"
blue = "#7d82d9"
magenta = "#c89dc1"
brown = "#75452a"
bright_red = "#faaaa9"
bright_yellow = "#f7dc9c"
bright_green = "#c4cfc4"
bright_cyan = "#dfeaf0"
bright_blue = "#c2c4f0"
bright_magenta = "#ead7e7"')
gen "$T"
assert_eq "semantic: neovim.lua written" "yes" "$([[ -f "$T/neovim.lua" ]] && echo yes || echo no)"
assert_not_contains "semantic: every placeholder filled" "$(cat "$T/neovim.lua")" "{{"
assert_eq "semantic: background" "#060B1E" "$(color "$T" bg)"
assert_eq "semantic: its own orange" "#eb8b54" "$(color "$T" orange)"
assert_eq "semantic: its own brown" "#75452a" "$(color "$T" brown)"
assert_contains "semantic: the aether plugin the package ships" "$(cat "$T/neovim.lua")" '"bjarneo/aether.nvim"'
assert_contains "semantic: its v3 branch, as the package has it" "$(cat "$T/neovim.lua")" 'branch = "v3"'
assert_eq "semantic: no name, so lazy finds the packaged copy" "" "$(grep -E '^ +name = ' "$T/neovim.lua")"
assert_contains "semantic: selects the aether colorscheme" "$(cat "$T/neovim.lua")" 'colorscheme = "aether"'
assert_eq "semantic: readable by everyone" "644" "$(stat -c %a "$T/neovim.lua")"

# --- missing orange and brown (Omarchy's white, last-horizon): Omarchy's fallbacks ---
T=$(theme no-orange 'background = "#ffffff"
foreground = "#000000"
yellow = "#808000"
accent = "#0000ff"')
gen "$T"
assert_eq "no orange: orange falls back to yellow" "#808000" "$(color "$T" orange)"
assert_eq "no brown: brown is orange mixed 50% with black" "#404000" "$(color "$T" brown)"
assert_eq "no dark_background: background mixed 25% with black" "#bfbfbf" "$(color "$T" dark_bg)"
assert_eq "no bright_yellow: yellow mixed 20% with white" "#999933" "$(color "$T" bright_yellow)"
assert_not_contains "no orange: every placeholder filled" "$(cat "$T/neovim.lua")" "{{"

# --- a legacy theme (only color0-15): the ANSI aliases ---
T=$(theme legacy "$(for i in $(seq 0 15); do printf 'color%d = "#%02x%02x%02x"\n' "$i" "$i" "$i" "$i"; done)")
gen "$T"
assert_eq "legacy: background from color0" "#000000" "$(color "$T" bg)"
assert_eq "legacy: foreground from color7" "#070707" "$(color "$T" fg)"
assert_eq "legacy: red from color1" "#010101" "$(color "$T" red)"
assert_eq "legacy: bright blue from color12" "#0c0c0c" "$(color "$T" bright_blue)"
assert_eq "legacy: muted from color8" "#080808" "$(color "$T" muted)"
assert_not_contains "legacy: every placeholder filled" "$(cat "$T/neovim.lua")" "{{"

# --- a theme's own neovim.lua always wins ---
T=$(theme own 'background = "#000000"
foreground = "#ffffff"')
echo 'return { "their own" }' >"$T/neovim.lua"
gen "$T"
assert_eq "own neovim.lua: left untouched" 'return { "their own" }' "$(cat "$T/neovim.lua")"

# --- no usable background/foreground: nothing written (LazyVim's colors, as before) ---
T=$(theme no-base 'accent = "#123456"')
gen "$T"
assert_eq "no background/foreground: nothing written" "no" "$([[ -e "$T/neovim.lua" ]] && echo yes || echo no)"

# --- hostile colors.toml: nothing that isn't #rrggbb reaches the Lua ---
T=$(theme hostile 'background = "#000000"
foreground = "#ffffff"
accent = "#fff\", os.execute(\"touch /tmp/pwned\") --"
red = "#ff0000\"; os.execute(\"id\")"
blue = "]]..os.execute(\"id\")..[["
green = "#00ff00"
selection = "#aabbccdd"')
gen "$T"
assert_eq "hostile: still written, from the valid colors" "yes" "$([[ -f "$T/neovim.lua" ]] && echo yes || echo no)"
assert_not_contains "hostile: no os.execute anywhere" "$(cat "$T/neovim.lua")" "os.execute"
assert_not_contains "hostile: no stray quote injection" "$(cat "$T/neovim.lua")" '\"'
assert_eq "hostile: a rejected red falls back to the foreground" "#ffffff" "$(color "$T" red)"
assert_eq "hostile: a valid color is still used" "#00ff00" "$(color "$T" green)"
assert_eq "hostile: an 8-digit color counts as missing" "no" "$(grep -q 'aabbccdd' "$T/neovim.lua" && echo yes || echo no)"
assert_eq "hostile: every value is a #rrggbb color" "" \
  "$(grep -E '^ +[a-z_]+ = "' "$T/neovim.lua" | grep -vE '= "(#[0-9A-Fa-f]{6}|v3|aether|bjarneo/aether.nvim)",?$' | grep -v 'colorscheme')"

# --- no colors.toml at all: nothing to do ---
mkdir -p "$MOCK_DIR/empty"
gen "$MOCK_DIR/empty"
assert_eq "no colors.toml: nothing written" "no" "$([[ -e "$MOCK_DIR/empty/neovim.lua" ]] && echo yes || echo no)"

mock_cleanup
test_summary
