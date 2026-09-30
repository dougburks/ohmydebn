#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-colors on Omarchy 4 "semantic"
# colors.toml files (named colors, no color0-15). The script copies the
# theme's file and appends the legacy aliases OhMyDebn's templates expect
# (cursor, selection_*, color0-15). It appended cursor/selection_* even
# when the theme already set them - Aether's themes (4.29.9+) set
# selection_foreground - which made a colors.toml strict TOML rejects
# ("Cannot overwrite a value"): the doctor failed it and the theme
# carousel lost the theme's accent. Only missing aliases may be added, and
# the result must parse as TOML.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-colors"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-colors (semantic colors.toml) ==="

SCRATCH=$(mktemp -d)

# convert <name> <colors.toml content>: prints the path of the result
convert() {
  mkdir -p "$SCRATCH/$1"
  printf '%s\n' "$2" >"$SCRATCH/$1/colors.toml"
  bash "$SCRIPT" "$SCRATCH/$1" </dev/null 2>/dev/null
}
parses() { python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1" 2>/dev/null && echo yes || echo no; }
count() { grep -cE "^\s*$2\s*=" "$1"; }
value() { grep -E "^\s*$2\s*=" "$1" | head -1 | sed -E 's/.*=\s*"([^"]*)".*/\1/'; }

BASE='mode = "dark"
accent = "#6473dc"
background = "#0b020f"
foreground = "#F7E1B1"
bright_foreground = "#f9e9c5"
selection = "#231b27"
red = "#e27355"
green = "#ff96ac"
yellow = "#ffc2dd"
blue = "#6473dc"
magenta = "#b15fb8"
cyan = "#6f7de7"'

# --- Aether (selection_foreground set by the theme): kept once, as the theme's ---
OUT=$(convert aether "$BASE
selection_foreground = \"#0b020f\"")
assert_eq "Aether: result parses as TOML" "yes" "$(parses "$OUT")"
assert_eq "Aether: selection_foreground only once" "1" "$(count "$OUT" selection_foreground)"
assert_eq "Aether: the theme's own selection_foreground kept" "#0b020f" "$(value "$OUT" selection_foreground)"
assert_eq "Aether: missing selection_background added" "#231b27" "$(value "$OUT" selection_background)"
assert_eq "Aether: missing cursor added" "#f9e9c5" "$(value "$OUT" cursor)"
assert_eq "Aether: color0 added" "#0b020f" "$(value "$OUT" color0)"
rm -f "$OUT"

# --- a stock Omarchy semantic theme (none of the three set): all added ---
OUT=$(convert stock "$BASE")
assert_eq "stock: result parses as TOML" "yes" "$(parses "$OUT")"
assert_eq "stock: selection_foreground added from bright_foreground" "#f9e9c5" "$(value "$OUT" selection_foreground)"
assert_eq "stock: cursor added" "1" "$(count "$OUT" cursor)"
rm -f "$OUT"

# --- a theme that sets all three: nothing duplicated ---
OUT=$(convert all "$BASE
cursor = \"#111111\"
selection_foreground = \"#222222\"
selection_background = \"#333333\"")
assert_eq "all set: result parses as TOML" "yes" "$(parses "$OUT")"
assert_eq "all set: the theme's cursor kept" "#111111" "$(value "$OUT" cursor)"
assert_eq "all set: selection_background only once" "1" "$(count "$OUT" selection_background)"
rm -f "$OUT"

rm -rf "$SCRATCH"
test_summary
