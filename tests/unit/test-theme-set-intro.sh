#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set's part in theme intros: the new
# background is chosen and its intro started (ohmydebn-theme-intro --wait)
# before anything on screen changes, so the switch happens underneath the
# clip; an intro is asked for only when the theme actually changes, not
# when the same one is applied again (by an update, a config reset or
# Aether); and a theme's intros/ folder is never copied into
# ~/.config/ohmydebn/current/theme, since intro clips run to megabytes and
# are played from where they are.
#
# HOME and the stock themes folder are scratch directories, and every
# script theme-set calls is a stand-in that logs its arguments.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set (theme intros) ==="

COLORS='accent = "#7aa2f7"
background = "#1a1b26"
foreground = "#a9b1d6"'

setup() {
  mock_init
  H="$MOCK_DIR/home"
  STOCK="$MOCK_DIR/stock"
  mkdir -p "$H/.config/ohmydebn/themes" "$H/.config/ohmydebn/current" "$STOCK/retro-82/backgrounds/intros"
  echo "$COLORS" >"$STOCK/retro-82/colors.toml"
  : >"$STOCK/retro-82/backgrounds/1-in-the-groove.jpg"
  : >"$STOCK/retro-82/backgrounds/2-dusk-guardian.jpg"
  : >"$STOCK/retro-82/backgrounds/intros/1-in-the-groove.webm"
  echo nord >"$H/.config/ohmydebn/current/theme.name"

  for cmd in ohmydebn-theme-set-templates ohmydebn-theme-set-cinnamon ohmydebn-theme-set-picker \
    ohmydebn-theme-set-claude ohmydebn-theme-set-t3code ohmydebn-theme-set-omp \
    ohmydebn-theme-set-colors-delete ohmydebn-theme-set-icon ohmydebn-theme-set-terminal \
    ohmydebn-theme-set-btop ohmydebn-theme-set-gedit ohmydebn-theme-set-starship \
    ohmydebn-theme-set-antigravity ohmydebn-theme-set-cava ohmydebn-theme-set-eza \
    ohmydebn-theme-set-fastfetch ohmydebn-theme-set-logo ohmydebn-theme-set-menu-icon \
    ohmydebn-theme-set-opencode ohmydebn-theme-set-vscode; do
    mock_bin "$cmd" <<'EOF'
#!/bin/bash
exit 0
EOF
  done
  mock_bin ohmydebn-theme-set-colors <<'EOF'
#!/bin/bash
echo ""
EOF
  mock_bin gsettings <<'EOF'
#!/bin/bash
mock_log "gsettings $*"
EOF
  # The theme's first background, from the copy theme-set just made (as the
  # real one picks it), or the N-th with --background N.
  mock_bin ohmydebn-theme-bg-next <<'EOF'
#!/bin/bash
mock_log "bg-next $*"
[[ -n "${MOCK_NO_BACKGROUNDS:-}" ]] && exit 0
n=1
[[ "${2:-}" == --background ]] && n=$3
find "$HOME/.config/ohmydebn/current/theme/backgrounds" -maxdepth 1 -type f | sort | sed -n "${n}p"
EOF
  mock_bin ohmydebn-theme-bg-set <<'EOF'
#!/bin/bash
mock_log "bg-set $*"
EOF
  mock_bin ohmydebn-theme-intro <<'EOF'
#!/bin/bash
mock_log "intro $*"
EOF
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/share/ohmydebn-themes#$STOCK#g" \
    "$REPO_ROOT/bin/ohmydebn-theme-set" >"$MOCK_DIR/theme-set"
}
set_theme() { HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/theme-set" "$@" </dev/null >"$MOCK_DIR/out" 2>&1; }
calls() { cat "$MOCK_CALLS"; }
# The line number of the first call matching $1, for checking order.
line_of() { grep -n -m1 -- "$1" "$MOCK_CALLS" | cut -d: -f1; }
BG() { echo "$H/.config/ohmydebn/current/theme/backgrounds/$1"; }

# --- switching to a theme: its intro starts before anything changes ---
setup
set_theme retro-82
CALLS=$(calls)
assert_eq "switch: succeeds" "" "$(grep -v '^$' "$MOCK_DIR/out")"
assert_contains "switch: the background is chosen without being set" "$CALLS" "bg-next --print"
assert_contains "switch: its intro is started and waited for" "$CALLS" "intro --wait $(BG 1-in-the-groove.jpg)"
assert_contains "switch: then that background is set" "$CALLS" "bg-set $(BG 1-in-the-groove.jpg)"
assert_eq "switch: the intro starts before the colors change" "yes" \
  "$([ "$(line_of intro)" -lt "$(line_of 'gsettings set')" ] && echo yes || echo no)"
assert_eq "switch: ...and before the background changes" "yes" \
  "$([ "$(line_of intro)" -lt "$(line_of bg-set)" ] && echo yes || echo no)"
assert_eq "switch: the theme's backgrounds are copied" "yes" \
  "$([ -f "$(BG 1-in-the-groove.jpg)" ] && [ -f "$(BG 2-dusk-guardian.jpg)" ] && echo yes || echo no)"
assert_eq "switch: its intros aren't" "no" "$([ -e "$(BG intros)" ] && echo yes || echo no)"
mock_cleanup

setup
set_theme --background 2 retro-82
assert_contains "--background N: the N-th is chosen" "$(calls)" "bg-next --print --background 2"
assert_contains "--background N: ...and set" "$(calls)" "bg-set $(BG 2-dusk-guardian.jpg)"
mock_cleanup

# --- a first install: no theme before, so no intro over the installer ---
setup
rm "$H/.config/ohmydebn/current/theme.name"
set_theme retro-82
assert_not_contains "first theme ever (install): no intro" "$(calls)" "intro"
assert_contains "first theme ever: the background is still set" "$(calls)" "bg-set $(BG 1-in-the-groove.jpg)"
mock_cleanup

# --- the same theme applied again: no intro ---
setup
echo retro-82 >"$H/.config/ohmydebn/current/theme.name"
set_theme retro-82
assert_not_contains "same theme again: no intro" "$(calls)" "intro"
assert_contains "same theme again: the background is still set" "$(calls)" "bg-set $(BG 1-in-the-groove.jpg)"
mock_cleanup

setup
MOCK_NO_BACKGROUNDS=1 set_theme retro-82
assert_not_contains "no background found: no intro" "$(calls)" "intro"
assert_not_contains "no background found: nothing set" "$(calls)" "bg-set"
mock_cleanup

# --- --keep-background: the kept image is the one an intro is looked for ---
setup
: >"$MOCK_DIR/kept.png"
ln -s "$MOCK_DIR/kept.png" "$H/.config/ohmydebn/current/background"
set_theme --keep-background retro-82
assert_contains "--keep-background: the kept image's intro is asked for" "$(calls)" "intro --wait $MOCK_DIR/kept.png"
assert_contains "--keep-background: and it stays the background" "$(calls)" "bg-set $MOCK_DIR/kept.png"
assert_not_contains "--keep-background: no other background chosen" "$(calls)" "bg-next"
mock_cleanup

# --- a theme from a git repo: its intros aren't copied either ---
setup
REPO_THEME="$H/.config/ohmydebn/themes/stranger"
mkdir -p "$REPO_THEME/.git" "$REPO_THEME/backgrounds/intros"
echo "$COLORS" >"$REPO_THEME/colors.toml"
: >"$REPO_THEME/backgrounds/one.png"
: >"$REPO_THEME/backgrounds/intros/one.webm"
set_theme stranger
assert_eq "theme from a git repo: its backgrounds are copied" "yes" "$([ -f "$(BG one.png)" ] && echo yes || echo no)"
assert_eq "theme from a git repo: its intros aren't" "no" "$([ -e "$(BG intros)" ] && echo yes || echo no)"
mock_cleanup

test_summary
