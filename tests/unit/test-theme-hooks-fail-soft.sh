#!/bin/bash
#
# Unit tests for theme hooks that must not fail when there's nothing they
# can safely change. ohmydebn-theme-set runs every hook under set -e, so a
# hook that exits non-zero skips all the hooks after it (terminal, btop,
# icons, starship...) and leaves the theme half-applied.
#
# - bin/ohmydebn-theme-set-claude: a ~/.claude/settings.json that isn't
#   valid JSON is left alone; a valid one gets the theme, written next to
#   the real file so a dotfiles symlink stays a symlink.
# - bin/ohmydebn-theme-set-cava: a missing cava config, or one without a
#   [color] section (someone who had their own ~/.config/cava), is skipped.
#
# HOME is a scratch directory, so nothing here touches the real ~/.claude
# or ~/.config/cava.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

COLORS="$REPO_ROOT/themes/ohmydebn/colors.toml"

echo "=== theme hooks fail soft (claude, cava) ==="

# --- claude: invalid settings.json is left alone, hook succeeds ---
mock_init
mkdir -p "$MOCK_DIR/home/.claude"
echo '{ not json' >"$MOCK_DIR/home/.claude/settings.json"
HOME="$MOCK_DIR/home" bash "$REPO_ROOT/bin/ohmydebn-theme-set-claude" ohmydebn "$COLORS" false </dev/null >/dev/null 2>&1
assert_eq "claude, invalid settings.json: exits 0" "0" "$?"
assert_eq "claude, invalid settings.json: left as it was" "{ not json" "$(cat "$MOCK_DIR/home/.claude/settings.json")"
assert_eq "claude, invalid settings.json: no temp file left behind" "" \
  "$(find "$MOCK_DIR/home/.claude" -maxdepth 1 -name 'settings.json.*')"
mock_cleanup

# --- claude: a symlinked settings.json stays a symlink and gets the theme ---
mock_init
mkdir -p "$MOCK_DIR/home/.claude" "$MOCK_DIR/home/dotfiles"
echo '{"model": "opus"}' >"$MOCK_DIR/home/dotfiles/claude-settings.json"
ln -s "$MOCK_DIR/home/dotfiles/claude-settings.json" "$MOCK_DIR/home/.claude/settings.json"
HOME="$MOCK_DIR/home" bash "$REPO_ROOT/bin/ohmydebn-theme-set-claude" ohmydebn "$COLORS" false </dev/null >/dev/null 2>&1
assert_eq "claude, symlinked settings.json: exits 0" "0" "$?"
assert_eq "claude, symlinked settings.json: still a symlink" "yes" \
  "$([[ -L "$MOCK_DIR/home/.claude/settings.json" ]] && echo yes || echo no)"
assert_eq "claude, symlinked settings.json: theme set, other keys kept" "custom:ohmydebn-ohmydebn opus" \
  "$(jq -r '"\(.theme) \(.model)"' "$MOCK_DIR/home/dotfiles/claude-settings.json")"
mock_cleanup

# --- cava: no config / no [color] section, hook succeeds ---
mock_init
mkdir -p "$MOCK_DIR/home/.config/ohmydebn/current/theme"
cp "$COLORS" "$MOCK_DIR/home/.config/ohmydebn/current/theme/colors.toml"
HOME="$MOCK_DIR/home" bash "$REPO_ROOT/bin/ohmydebn-theme-set-cava" </dev/null >/dev/null 2>&1
assert_eq "cava, no config: exits 0" "0" "$?"
mkdir -p "$MOCK_DIR/home/.config/cava"
printf '[general]\nframerate = 60\n' >"$MOCK_DIR/home/.config/cava/config"
HOME="$MOCK_DIR/home" bash "$REPO_ROOT/bin/ohmydebn-theme-set-cava" </dev/null >/dev/null 2>&1
assert_eq "cava, no [color] section: exits 0" "0" "$?"
assert_eq "cava, no [color] section: config untouched" "$(printf '[general]\nframerate = 60')" \
  "$(cat "$MOCK_DIR/home/.config/cava/config")"
mock_cleanup

test_summary
