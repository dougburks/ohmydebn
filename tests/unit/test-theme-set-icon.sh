#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-icon. The curated name-based table at
# the top only covers ohmydebn's own built-in themes; anything else (most
# importantly every theme applied via the Aether URL handler, which gets a
# unique generated name like "bridge-palette" that never matches the table)
# falls into the catch-all branch. That branch used to trust the icons.theme
# file the applied theme shipped - but Aether's own accent-to-icon guess was
# observed to be unreliable (e.g. an olive-green accent labeled
# Yaru-magenta), which is what made icons keep landing on Mint-Y-Purple
# regardless of the theme's actual colors. The catch-all now derives the icon
# theme from the theme's own accent color (already normalized into every
# theme's colors.toml by ohmydebn-theme-set-colors) instead, falling back to
# the old icons.theme string match only when no accent is present at all.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-icon"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-icon ==="

run_with() {
  local scratch_home="$1"
  mock_bin gsettings <<'EOF'
#!/bin/bash
mock_log "$*"
EOF
  HOME="$scratch_home" PATH="$(mock_path)" bash "$SCRIPT" >/dev/null 2>&1
}

set_theme_name() {
  local scratch_home="$1" name="$2"
  mkdir -p "$scratch_home/.config/ohmydebn/current"
  echo "$name" >"$scratch_home/.config/ohmydebn/current/theme.name"
}

set_accent() {
  local scratch_home="$1" accent="$2"
  mkdir -p "$scratch_home/.config/ohmydebn/current/theme"
  echo "accent = \"$accent\"" >>"$scratch_home/.config/ohmydebn/current/theme/colors.toml"
}

set_icons_theme() {
  local scratch_home="$1" value="$2"
  mkdir -p "$scratch_home/.config/ohmydebn/current/theme"
  echo "$value" >"$scratch_home/.config/ohmydebn/current/theme/icons.theme"
}

# Scenario 1: a curated built-in theme name always wins, regardless of
# whatever accent color or icons.theme happens to be sitting in current/theme
# (unchanged behavior - the accent-based bucketing below only applies to
# themes the curated table doesn't recognize).
mock_init
SCRATCH_HOME=$(mktemp -d)
set_theme_name "$SCRATCH_HOME" "gruvbox"
set_accent "$SCRATCH_HOME" "#ff00ff"
run_with "$SCRATCH_HOME"
assert_contains "curated name (gruvbox) wins over any accent color" "$(cat "$MOCK_CALLS")" \
  "set org.cinnamon.desktop.interface icon-theme Mint-Y"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2 (the reported bug): an Aether-style generated theme name with a
# blue accent but a misleading Yaru-magenta icons.theme guess must resolve to
# blue, not purple - accent color now wins over the shipped guess.
mock_init
SCRATCH_HOME=$(mktemp -d)
set_theme_name "$SCRATCH_HOME" "bridge-palette"
set_accent "$SCRATCH_HOME" "#5a7fd4"
set_icons_theme "$SCRATCH_HOME" "Yaru-magenta"
run_with "$SCRATCH_HOME"
assert_contains "accent color overrides a misleading icons.theme guess" "$(cat "$MOCK_CALLS")" \
  "set org.cinnamon.desktop.interface icon-theme Mint-Y-Blue"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: an olive-green accent (the exact case observed to be
# mislabeled Yaru-magenta) buckets to the green Mint-Y variant.
mock_init
SCRATCH_HOME=$(mktemp -d)
set_theme_name "$SCRATCH_HOME" "a-cartoon-of-a-forest-with-mushrooms-palette"
set_accent "$SCRATCH_HOME" "#718b3a"
set_icons_theme "$SCRATCH_HOME" "Yaru-magenta"
run_with "$SCRATCH_HOME"
assert_contains "olive-green accent buckets to green, not the shipped guess" "$(cat "$MOCK_CALLS")" \
  "set org.cinnamon.desktop.interface icon-theme Mint-Y"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 4: a desaturated/grey accent buckets to grey regardless of hue.
mock_init
SCRATCH_HOME=$(mktemp -d)
set_theme_name "$SCRATCH_HOME" "some-unnamed-theme"
set_accent "$SCRATCH_HOME" "#808080"
run_with "$SCRATCH_HOME"
assert_contains "desaturated accent buckets to grey" "$(cat "$MOCK_CALLS")" \
  "set org.cinnamon.desktop.interface icon-theme Mint-Y-Grey"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 5: no accent at all (legacy colors.toml) falls back to matching
# the shipped icons.theme by name, same as before this change.
mock_init
SCRATCH_HOME=$(mktemp -d)
set_theme_name "$SCRATCH_HOME" "some-legacy-theme"
set_icons_theme "$SCRATCH_HOME" "Yaru-red"
run_with "$SCRATCH_HOME"
assert_contains "no accent: falls back to icons.theme name matching" "$(cat "$MOCK_CALLS")" \
  "set org.cinnamon.desktop.interface icon-theme Mint-Y-Red"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 6: neither accent nor icons.theme present falls back to the
# overall default.
mock_init
SCRATCH_HOME=$(mktemp -d)
set_theme_name "$SCRATCH_HOME" "some-bare-theme"
run_with "$SCRATCH_HOME"
assert_contains "neither accent nor icons.theme: default grey" "$(cat "$MOCK_CALLS")" \
  "set org.cinnamon.desktop.interface icon-theme Mint-Y-Grey"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
