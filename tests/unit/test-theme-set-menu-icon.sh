#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-menu-icon: swaps the OhMyDebn Menu
# launcher between the solid (dark themes) and outline (light themes)
# symbolic icons without touching an icon the user chose, and writes the
# full-color ohmydebn icon in the theme's logo gradient. The real
# ohmydebn-theme-logo-colors supplies the gradient.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-menu-icon"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-menu-icon ==="

mock_init
sed -e "s#/usr/share/ohmydebn/bin#$REPO_ROOT/bin#g" \
  -e "s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" "$SCRIPT" >"$MOCK_DIR/hook.sh"

new_home() {
  SCRATCH_HOME=$(mktemp -d)
  LAUNCHER="$SCRATCH_HOME/.local/share/applications/ohmydebn-menu.desktop"
  ICON="$SCRATCH_HOME/.local/share/icons/hicolor/scalable/apps/ohmydebn.svg"
  THEME="$SCRATCH_HOME/.config/ohmydebn/current/theme"
  mkdir -p "$(dirname "$LAUNCHER")" "$THEME"
  printf '[Desktop Entry]\nName=OhMyDebn Menu\nIcon=%s\nType=Application\n' "${1:-ohmydebn-menu-symbolic}" >"$LAUNCHER"
}

run_hook() {
  HOME="$SCRATCH_HOME" bash "$MOCK_DIR/hook.sh" "$@" </dev/null >"$MOCK_DIR/out" 2>&1
}

launcher_icon() {
  sed -n 's/^Icon=//p' "$LAUNCHER"
}

DARK='mode = "dark"
accent = "#7aa2f7"
background = "#1a1b26"
foreground = "#a9b1d6"
blue = "#7aa2f7"
cyan = "#449dab"'
LIGHT='mode = "light"
accent = "#1e66f5"
background = "#eff1f5"
foreground = "#4c4f69"
blue = "#1e66f5"
cyan = "#179299"'

# Scenario 1: no theme yet - solid icon, and the full-color icon comes out
# exactly as the default the package ships.
new_home
run_hook
assert_eq "no theme: hook succeeds" "0" "$?"
assert_eq "no theme: launcher stays solid" "ohmydebn-menu-symbolic" "$(launcher_icon)"
assert_eq "no theme: full-color icon matches the packaged default" \
  "$(cat "$REPO_ROOT/config/icons/ohmydebn.svg")" "$(cat "$ICON")"
rm -rf "$SCRATCH_HOME"

# Scenario 2: a dark theme - solid icon; gradient from the theme's accent,
# blue and cyan (de-duplicated); eyes and mouth in the background color.
new_home
printf '%s\n' "$DARK" >"$THEME/colors.toml"
run_hook
assert_eq "dark: launcher solid" "ohmydebn-menu-symbolic" "$(launcher_icon)"
SVG=$(cat "$ICON")
assert_contains "dark: gradient starts at the accent" "$SVG" '<stop offset="0" stop-color="#7aa2f7"/>'
assert_contains "dark: gradient ends at cyan" "$SVG" '<stop offset="1" stop-color="#449dab"/>'
assert_not_contains "dark: blue (same as accent) not repeated" "$SVG" 'offset="0.5"'
assert_contains "dark: features in the background color" "$SVG" 'fill="#1a1b26"'
assert_not_contains "dark: no placeholder left" "$SVG" "{{"
rm -rf "$SCRATCH_HOME"

# Scenario 3: a light theme - outline icon, features in the text color.
new_home
printf '%s\n' "$LIGHT" >"$THEME/colors.toml"
run_hook
assert_eq "light: launcher switches to outline" "ohmydebn-menu-outline-symbolic" "$(launcher_icon)"
assert_contains "light: features in the text color" "$(cat "$ICON")" 'fill="#4c4f69"'
# ...and back to a dark theme.
printf '%s\n' "$DARK" >"$THEME/colors.toml"
run_hook
assert_eq "light -> dark: launcher back to solid" "ohmydebn-menu-symbolic" "$(launcher_icon)"
rm -rf "$SCRATCH_HOME"

# Scenario 4: an older theme marks light mode with a light.mode file, and
# ohmydebn-theme-set's own argument wins over the theme file.
new_home
: >"$THEME/light.mode"
run_hook
assert_eq "light.mode marker: outline" "ohmydebn-menu-outline-symbolic" "$(launcher_icon)"
run_hook false
assert_eq "argument false: solid" "ohmydebn-menu-symbolic" "$(launcher_icon)"
rm -rf "$SCRATCH_HOME"

# Scenario 5: an icon the user chose stays, on any theme, and nothing else
# in the launcher changes.
new_home my-favorite-icon
printf '%s\n' "$LIGHT" >"$THEME/colors.toml"
BEFORE=$(cat "$LAUNCHER")
run_hook
assert_eq "custom icon: launcher left alone" "$BEFORE" "$(cat "$LAUNCHER")"
rm -rf "$SCRATCH_HOME"

# Scenario 6: a theme's colors can't inject markup into the SVG - anything
# but a plain hex color falls back to the default.
new_home
printf 'mode = "dark"\naccent = "#7aa2f7"\nbackground = "#1a1b26\\"/><script>x</script>"\n' >"$THEME/colors.toml"
run_hook
assert_not_contains "bad color: no markup injected" "$(cat "$ICON")" "<script>"
assert_contains "bad color: features fall back to the default" "$(cat "$ICON")" 'fill="#1e1e2e"'
rm -rf "$SCRATCH_HOME"

# Scenario 7: a launcher that's missing is fine (the install step writes it
# later), and an unchanged icon isn't rewritten.
new_home
rm "$LAUNCHER"
run_hook
assert_eq "no launcher: hook succeeds" "0" "$?"
touch -d '2001-01-01' "$ICON"
run_hook
assert_eq "unchanged icon: not rewritten" "2001-01-01" "$(date -r "$ICON" +%F)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
