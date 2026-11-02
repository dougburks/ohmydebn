#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-terminal: it tells Alacritty whether
# its window decorations should be light or dark, editing alacritty.toml in
# place. An alacritty.toml that's a symlink (into a dotfiles repo) used to
# be replaced by a plain file there (sed -i writes a new file), so the
# dotfiles repo silently stopped being used. HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-terminal ==="

run() {
  HOME="$H" PATH="$(mock_path)" bash "$REPO_ROOT/bin/ohmydebn-theme-set-terminal" "$1" </dev/null >/dev/null 2>&1
  STATUS=$?
}

# A plain config: the variant is set, and then changed in place.
mock_init
H="$MOCK_DIR/home"
mkdir -p "$H/.config/alacritty"
printf '[window]\npadding = { x = 8, y = 8 }\n' >"$H/.config/alacritty/alacritty.toml"
run false
assert_eq "plain config: exits 0" "0" "$STATUS"
assert_contains "plain config: dark variant added under [window]" "$(cat "$H/.config/alacritty/alacritty.toml")" $'[window]\ndecorations_theme_variant = "Dark"'
run true
assert_eq "plain config: switched to light, once" "1" "$(grep -c 'decorations_theme_variant = "Light"' "$H/.config/alacritty/alacritty.toml")"
mock_cleanup

# A config that's a symlink: edited where it points, and stays a link.
mock_init
H="$MOCK_DIR/home"
mkdir -p "$H/.config/alacritty" "$H/dotfiles"
printf '[window]\ndecorations_theme_variant = "Dark"\n' >"$H/dotfiles/alacritty.toml"
ln -s "$H/dotfiles/alacritty.toml" "$H/.config/alacritty/alacritty.toml"
run true
assert_eq "symlinked config: still a symlink" "yes" "$([ -L "$H/.config/alacritty/alacritty.toml" ] && echo yes || echo no)"
assert_contains "symlinked config: the file it points to is changed" "$(cat "$H/dotfiles/alacritty.toml")" 'decorations_theme_variant = "Light"'
mock_cleanup

test_summary
