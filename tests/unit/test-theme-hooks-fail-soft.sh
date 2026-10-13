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

# The Claude Code hook does nothing unless Claude Code is installed, so
# these runs say it is (a `claude` on PATH) whatever this machine has,
# with dpkg saying the claude-code package isn't. Call after mock_init.
run_claude_hook() {
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 1
STUB
  if [[ "${NO_CLAUDE:-}" != 1 ]]; then
    mock_bin claude <<'STUB'
#!/bin/bash
exit 0
STUB
  fi
  # Only the mocks and the basics the hook needs, so a real `claude`
  # elsewhere on this machine's PATH can't count.
  mkdir -p "$MOCK_DIR/sysbin"
  for tool in jq mktemp mv rm cat chmod grep sed mkdir basename dirname readlink head seq diff; do
    ln -sf "$(command -v "$tool")" "$MOCK_DIR/sysbin/$tool"
  done
  HOME="$MOCK_DIR/home" PATH="$MOCK_BIN:$MOCK_DIR/sysbin" /bin/bash "$REPO_ROOT/bin/ohmydebn-theme-set-claude" "$@" </dev/null >/dev/null 2>&1
}

# --- claude: invalid settings.json is left alone, hook succeeds ---
mock_init
mkdir -p "$MOCK_DIR/home/.claude"
echo '{ not json' >"$MOCK_DIR/home/.claude/settings.json"
run_claude_hook ohmydebn "$COLORS" false
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
run_claude_hook ohmydebn "$COLORS" false
assert_eq "claude, symlinked settings.json: exits 0" "0" "$?"
assert_eq "claude, symlinked settings.json: still a symlink" "yes" \
  "$([[ -L "$MOCK_DIR/home/.claude/settings.json" ]] && echo yes || echo no)"
assert_eq "claude, symlinked settings.json: theme set, other keys kept" "custom:ohmydebn-ohmydebn opus" \
  "$(jq -r '"\(.theme) \(.model)"' "$MOCK_DIR/home/dotfiles/claude-settings.json")"
mock_cleanup

# --- claude: themes from earlier switches go once the new one is selected ---
mock_init
mkdir -p "$MOCK_DIR/home/.claude/themes"
echo '{}' >"$MOCK_DIR/home/.claude/settings.json"
for old in ohmydebn-gruvbox ohmydebn-a-aerial-view-of-a-snowy-mountain-palette; do
  echo '{}' >"$MOCK_DIR/home/.claude/themes/$old.json"
done
echo '{}' >"$MOCK_DIR/home/.claude/themes/my-own.json"
run_claude_hook ohmydebn "$COLORS" false
assert_eq "claude: only the current OhMyDebn theme file is left, the user's own kept" \
  "my-own.json ohmydebn-ohmydebn.json" "$(cd "$MOCK_DIR/home/.claude/themes" && ls | tr '\n' ' ' | sed 's/ $//')"
mock_cleanup

# --- claude: settings.json not valid -> no theme file removed, since
# Claude Code may still be pointing at one of them ---
mock_init
mkdir -p "$MOCK_DIR/home/.claude/themes"
echo '{ not json' >"$MOCK_DIR/home/.claude/settings.json"
echo '{}' >"$MOCK_DIR/home/.claude/themes/ohmydebn-gruvbox.json"
run_claude_hook ohmydebn "$COLORS" false
assert_eq "claude, settings not updated: the earlier theme file is kept" "yes" \
  "$([ -f "$MOCK_DIR/home/.claude/themes/ohmydebn-gruvbox.json" ] && echo yes || echo no)"
mock_cleanup

# --- claude: not installed -> nothing written, not even ~/.claude ---
mock_init
mkdir -p "$MOCK_DIR/home"
NO_CLAUDE=1 run_claude_hook ohmydebn "$COLORS" false
STATUS=$?
assert_eq "claude, not installed: exits 0" "0" "$STATUS"
assert_eq "claude, not installed: no ~/.claude written" "no" "$([ -e "$MOCK_DIR/home/.claude" ] && echo yes || echo no)"
mock_cleanup

# --- claude: --current themes it with the theme already applied, as
# ohmydebn-claude-code-install does right after installing it ---
mock_init
mkdir -p "$MOCK_DIR/home/.config/ohmydebn/current/theme"
echo "osaka-jade" >"$MOCK_DIR/home/.config/ohmydebn/current/theme.name"
cp "$COLORS" "$MOCK_DIR/home/.config/ohmydebn/current/theme/colors.toml"
run_claude_hook --current
STATUS=$?
assert_eq "claude --current: exits 0" "0" "$STATUS"
assert_eq "claude --current: the current theme's file is written" "yes" \
  "$([ -f "$MOCK_DIR/home/.claude/themes/ohmydebn-osaka-jade.json" ] && echo yes || echo no)"
assert_eq "claude --current: and selected" '"custom:ohmydebn-osaka-jade"' \
  "$(jq '.theme' "$MOCK_DIR/home/.claude/settings.json" 2>/dev/null)"
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
