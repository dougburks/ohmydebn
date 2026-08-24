#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set's filtering of themes installed from a
# git repo (via ohmydebn-theme-install). A theme cloned from a stranger's repo
# is held to a short allow-list - color and image files only - because Neovim
# loads a theme's neovim.lua at startup, Alacritty's alacritty.toml names the
# program a new terminal launches, and vscode.json names a VS Code extension
# ohmydebn-theme-set-vscode installs. A theme the user wrote themselves (no
# .git left behind) is not filtered at all. Every downstream theming script is
# stubbed out here so this only exercises what gets staged into
# ~/.config/ohmydebn/current/theme, not the scripts that read it afterward.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set (installed-theme staging) ==="

setup_mocks() {
  for cmd in ohmydebn-theme-set-templates ohmydebn-theme-bg-next \
    ohmydebn-theme-set-cinnamon ohmydebn-theme-set-picker ohmydebn-theme-set-claude \
    ohmydebn-theme-set-colors-delete ohmydebn-theme-set-icon ohmydebn-theme-set-terminal \
    ohmydebn-theme-set-btop ohmydebn-theme-set-gedit ohmydebn-theme-set-starship \
    ohmydebn-theme-set-antigravity ohmydebn-theme-set-cava ohmydebn-theme-set-eza \
    ohmydebn-theme-set-fastfetch ohmydebn-theme-set-opencode ohmydebn-theme-set-vscode; do
    mock_bin "$cmd" <<'EOF'
#!/bin/bash
exit 0
EOF
  done
  # Real color resolution isn't under test here; an empty result skips the
  # copy-over-colors.toml branch in ohmydebn-theme-set and leaves whatever
  # staging already produced in place.
  mock_bin ohmydebn-theme-set-colors <<'EOF'
#!/bin/bash
echo ""
EOF
  mock_bin gsettings <<'EOF'
#!/bin/bash
exit 0
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/theme-set-patched.sh"
}

set_theme() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/theme-set-patched.sh" "$1" >"$MOCK_DIR/out" 2>&1
}

staged() {
  printf '%s' "$SCRATCH_HOME/.config/ohmydebn/current/theme/$1"
}

mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
THEMES="$SCRATCH_HOME/.config/ohmydebn/themes"
mkdir -p "$THEMES"

# --- A theme installed from a git repo ships everything it is not allowed to ship ---
hostile="$THEMES/hostile"
mkdir -p "$hostile/.git" "$hostile/backgrounds"
cat >"$hostile/colors.toml" <<'TOML'
accent = "#7aa2f7"
background = "#1a1b26"
foreground = "#a9b1d6"
color0 = "#1a1b26"
color1 = "#f7768e"
color2 = "#9ece6a"
color3 = "#e0af68"
color4 = "#7aa2f7"
color5 = "#bb9af7"
color6 = "#7dcfff"
color7 = "#a9b1d6"
TOML
printf 'vim.cmd("os.execute(id)")\n' >"$hostile/neovim.lua"
printf '[terminal.shell]\nprogram = "pwned"\n' >"$hostile/alacritty.toml"
printf '{"name":"x","extension":"pub.ext"}\n' >"$hostile/vscode.json"
printf 'Yaru-red\n' >"$hostile/icons.theme"
printf 'png\n' >"$hostile/backgrounds/1-real.png"
printf '# notes\n' >"$hostile/README.md"
ln -s /etc/hostname "$hostile/unlock.png"

if ! set_theme hostile; then
  assert_eq "applies a theme that ships disallowed files" "ok" "FAILED: $(cat "$MOCK_DIR/out")"
fi

[[ -f $(staged colors.toml) ]] && assert_eq "the theme's colors.toml is staged" "yes" "yes" || assert_eq "the theme's colors.toml is staged" "yes" "no"
[[ -f $(staged backgrounds/1-real.png) ]] && assert_eq "an image in backgrounds/ is staged" "yes" "yes" || assert_eq "an image in backgrounds/ is staged" "yes" "no"
[[ -f $(staged icons.theme) ]] && assert_eq "icons.theme (color-only) is staged" "yes" "yes" || assert_eq "icons.theme (color-only) is staged" "yes" "no"

[[ ! -e $(staged neovim.lua) ]] && assert_eq "neovim.lua is not staged (Lua runs at startup)" "yes" "yes" || assert_eq "neovim.lua is not staged (Lua runs at startup)" "yes" "no"
[[ ! -e $(staged alacritty.toml) ]] && assert_eq "alacritty.toml is not staged (names the shell to launch)" "yes" "yes" || assert_eq "alacritty.toml is not staged (names the shell to launch)" "yes" "no"
[[ ! -e $(staged vscode.json) ]] && assert_eq "vscode.json is not staged (names an extension to install)" "yes" "yes" || assert_eq "vscode.json is not staged (names an extension to install)" "yes" "no"
[[ ! -e $(staged unlock.png) ]] && assert_eq "a symlink is not followed out of the theme" "yes" "yes" || assert_eq "a symlink is not followed out of the theme" "yes" "no"
[[ ! -e $(staged .git) ]] && assert_eq "the clone's own .git directory is never staged" "yes" "yes" || assert_eq "the clone's own .git directory is never staged" "yes" "no"

assert_contains "ohmydebn-theme-set names the files it ignored" "$(cat "$MOCK_DIR/out")" "neovim.lua"
assert_not_contains "ohmydebn-theme-set does not report a theme's documentation" "$(cat "$MOCK_DIR/out")" "README.md"

# --- A theme the user wrote themselves (no .git) is not filtered ---
mine="$THEMES/mine"
mkdir -p "$mine"
cp "$hostile/colors.toml" "$mine/colors.toml"
printf 'vim.cmd("keep me")\n' >"$mine/neovim.lua"
printf '{"name":"Mine","extension":"pub.ext"}\n' >"$mine/vscode.json"

set_theme mine || true
[[ -f $(staged neovim.lua) ]] && grep -q "keep me" "$(staged neovim.lua)" \
  && assert_eq "a theme the user wrote keeps its own neovim.lua" "yes" "yes" \
  || assert_eq "a theme the user wrote keeps its own neovim.lua" "yes" "no"
[[ -f $(staged vscode.json) ]] && assert_eq "a theme the user wrote keeps every file it ships" "yes" "yes" || assert_eq "a theme the user wrote keeps every file it ships" "yes" "no"

rm -rf "$SCRATCH_HOME"
mock_cleanup
test_summary
