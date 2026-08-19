#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-picker - computes the GTK pickers'
# small bg0/bg1/bg3/fg0 color file from a theme's resolved colors.toml,
# replacing the old rofi .rasi generation. Runs the real script with HOME
# redirected to a scratch dir (it hardcodes ~/.config/ohmydebn/current/
# picker-colors, not something this script's own args can override), so
# it never touches the real ~/.config/ohmydebn.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-picker"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-theme-set-picker ==="

SCRATCH_HOME=$(mktemp -d)
trap 'rm -rf "$SCRATCH_HOME"' EXIT

COLORS_FILE="$SCRATCH_HOME/colors.toml"
PICKER_COLORS_FILE="$SCRATCH_HOME/.config/ohmydebn/current/picker-colors"

cat >"$COLORS_FILE" <<'EOF'
background = "#2e3440"
foreground = "#d8dee9"
accent = "#81a1c1"
color0 = "#3b4252"
color7 = "#e5e9f0"
color8 = "#4c566a"
EOF

HOME="$SCRATCH_HOME" "$SCRIPT" "$COLORS_FILE"
OUTPUT=$(cat "$PICKER_COLORS_FILE" 2>&1)
assert_contains "writes bg0 from background, with the F2 alpha suffix" "$OUTPUT" "bg0=#2e3440F2"
assert_contains "writes bg1 from background, with no alpha suffix" "$OUTPUT" "bg1=#2e3440"
assert_contains "writes bg3 from accent, with the F2 alpha suffix" "$OUTPUT" "bg3=#81a1c1F2"
assert_contains "writes fg0 from foreground" "$OUTPUT" "fg0=#d8dee9"

# Regression guard: the old rofi version (ohmydebn-theme-set-rofi) took an
# <is-light-mode> argument and branched its bg0/bg1/bg3/fg0 formulas on it
# - but those formulas were confirmed identical in both branches (only the
# unused bg2/fg1/fg2/fg3 keys actually differed by mode). This script
# correctly dropped that argument entirely rather than porting a branch
# that never did anything - same output regardless of a 2nd/3rd arg.
rm -f "$PICKER_COLORS_FILE"
HOME="$SCRATCH_HOME" "$SCRIPT" "$COLORS_FILE" "some-theme-name" "true" "extra-arg-should-be-ignored"
OUTPUT=$(cat "$PICKER_COLORS_FILE" 2>&1)
assert_contains "ignores any extra positional arguments" "$OUTPUT" "bg0=#2e3440F2"

rm -f "$PICKER_COLORS_FILE"
HOME="$SCRATCH_HOME" "$SCRIPT" "/nonexistent/colors.toml"
assert_eq "missing colors source: creates no picker-colors file" "false" "$([ -f "$PICKER_COLORS_FILE" ] && echo true || echo false)"

mkdir -p "$(dirname "$PICKER_COLORS_FILE")"
echo "stale content from a previous theme" >"$PICKER_COLORS_FILE"
HOME="$SCRATCH_HOME" "$SCRIPT" ""
assert_eq "empty colors source: removes any stale picker-colors file" "false" "$([ -f "$PICKER_COLORS_FILE" ] && echo true || echo false)"

HOME="$SCRATCH_HOME" "$SCRIPT" >/dev/null 2>&1
EXIT_CODE=$?
assert_eq "called with zero arguments: exits 0 rather than erroring" "0" "$EXIT_CODE"

test_summary
