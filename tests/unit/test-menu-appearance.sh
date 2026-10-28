#!/bin/bash
#
# Unit tests for the OhMyDebn menu's Appearance menu, which took over the
# old Style menu and gathers everything about how the desktop looks:
# Background, Fonts and Panel joined what Style had. The Go menu must open
# it from its new name, and the menu search must list each item under it,
# with nothing left under Style.
#
# The search index comes from the real bin/ohmydebn-menu-tree reading the
# real bin/ohmydebn-menu; the Go dispatch from the menu's own go_to_menu(),
# sourced without its last line (which shows the menu) and with every
# show_*_menu it calls replaced by a stand-in that only logs.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-menu: the Appearance menu ==="

mock_init
# The menu tree caches its index under HOME.
export HOME="$MOCK_DIR/home"
mkdir -p "$HOME"

INDEX=$(bash -c 'source "$1"; menu_tree_flatten "$2"' _ \
  "$REPO_ROOT/bin/ohmydebn-menu-tree" "$REPO_ROOT/bin/ohmydebn-menu" 2>&1)

# --- each item is in the search, opening the right thing ---
CARD=/usr/share/ohmydebn/bin/ohmydebn-theme-carousel
for entry in \
  "Background	$CARD" \
  "Effects	cinnamon-settings effects" \
  "Fonts	cinnamon-settings fonts" \
  "Notifications	cinnamon-settings notifications" \
  "Panel	cinnamon-settings panel" \
  "Screensaver	cinnamon-settings screensaver" \
  "Theme	$CARD" \
  "Theme Intros	/usr/share/ohmydebn/bin/ohmydebn-theme-intro-toggle" \
  "Tiling	xlet-settings extension gTile@OhMyDebn" \
  "Windows	cinnamon-settings windows" \
  "Workspaces	cinnamon-settings workspaces"; do
  assert_eq "search: Appearance > ${entry%%	*}" "yes" \
    "$(grep -qxF "Appearance > $entry" <<<"$INDEX" && echo yes || echo no)"
done
assert_eq "search: nothing left under Style" "" "$(grep '^Style > ' <<<"$INDEX")"

# --- the Go menu opens it by its new name ---
GO=$(
  # shellcheck disable=SC1090
  source <(sed '/^show_main_menu$/d' "$REPO_ROOT/bin/ohmydebn-menu") 2>/dev/null
  for f in $(declare -F | awk '$3 ~ /^show_.*_menu$/ {print $3}'); do
    eval "$f() { echo $f; }"
  done
  go_to_menu "  Appearance"
  go_to_menu "󰀻  Apps"
)
assert_eq "Go: Appearance opens the Appearance menu, and Apps still Apps" \
  "show_appearance_menu
show_apps_menu" "$GO"

mock_cleanup
test_summary
