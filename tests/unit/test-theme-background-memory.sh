#!/bin/bash
#
# Unit tests for each theme remembering its background. Switching away
# from a theme and back used to show its first background, forgetting the
# one picked: ohmydebn-theme-set now records the background a theme was
# showing when it's left, ohmydebn-theme-bg-next brings it back when the
# theme is applied without --background, and the theme carousel starts on
# it, so Enter with no navigation applies it too.
#
# The real ohmydebn-theme-set and ohmydebn-theme-bg-next run together; HOME
# and the stock themes folder are scratch directories, the background is
# set by a stand-in that only moves the link (as the real one does, to the
# resolved path), and every other script theme-set calls is a stand-in.
# The carousel's choice comes from its own starting_background_index().

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== theme background memory: ohmydebn-theme-set, -bg-next, the carousel ==="

COLORS='accent = "#7aa2f7"
background = "#1a1b26"
foreground = "#a9b1d6"'

setup() {
  mock_init
  H="$MOCK_DIR/home"
  STOCK="$MOCK_DIR/stock"
  MEMORY="$H/.local/state/ohmydebn/theme-backgrounds"
  mkdir -p "$H/.config/ohmydebn/themes" "$H/.config/ohmydebn/current"
  for theme in aurora boreal; do
    mkdir -p "$STOCK/$theme/backgrounds"
    echo "$COLORS" >"$STOCK/$theme/colors.toml"
    for n in 1 2 3; do : >"$STOCK/$theme/backgrounds/$n-$theme.jpg"; done
  done
  for cmd in ohmydebn-theme-set-templates ohmydebn-theme-set-cinnamon ohmydebn-theme-set-picker \
    ohmydebn-theme-set-claude ohmydebn-theme-set-t3code ohmydebn-theme-set-omp \
    ohmydebn-theme-set-colors-delete ohmydebn-theme-set-icon ohmydebn-theme-set-terminal \
    ohmydebn-theme-set-btop ohmydebn-theme-set-gedit ohmydebn-theme-set-starship \
    ohmydebn-theme-set-antigravity ohmydebn-theme-set-cava ohmydebn-theme-set-eza \
    ohmydebn-theme-set-fastfetch ohmydebn-theme-set-logo ohmydebn-theme-set-menu-icon \
    ohmydebn-theme-set-opencode ohmydebn-theme-set-vscode ohmydebn-theme-intro gsettings notify-send; do
    printf '#!/bin/bash\nexit 0\n' | mock_bin "$cmd"
  done
  printf '#!/bin/bash\necho ""\n' | mock_bin ohmydebn-theme-set-colors
  mock_bin ohmydebn-theme-bg-set <<'EOF'
#!/bin/bash
ln -nsf "$(readlink -f -- "$1")" "$HOME/.config/ohmydebn/current/background"
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-theme-bg-next" >"$MOCK_BIN/ohmydebn-theme-bg-next"
  chmod +x "$MOCK_BIN/ohmydebn-theme-bg-next"
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/share/ohmydebn-themes#$STOCK#g" \
    "$REPO_ROOT/bin/ohmydebn-theme-set" >"$MOCK_DIR/theme-set"
}
set_theme() { HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/theme-set" "$@" </dev/null >"$MOCK_DIR/out" 2>&1; }
showing() { basename "$(readlink "$H/.config/ohmydebn/current/background" 2>/dev/null)"; }
exists() { [[ -e "$1" ]] && echo yes || echo no; }

# --- leaving a theme and coming back ---
setup
set_theme aurora
assert_eq "first theme ever: its first background" "1-aurora.jpg" "$(showing)"
set_theme --background 3 aurora
assert_eq "background 3 picked" "3-aurora.jpg" "$(showing)"
set_theme boreal
assert_eq "another theme, never shown before: its first" "1-boreal.jpg" "$(showing)"
assert_contains "the theme left records what it was showing" "$(cat "$MEMORY/aurora" 2>/dev/null)" "3-aurora.jpg"
set_theme --background 2 boreal
set_theme aurora
assert_eq "back to the first theme: the background it had" "3-aurora.jpg" "$(showing)"
set_theme boreal
assert_eq "and back to the other: the one it had" "2-boreal.jpg" "$(showing)"
set_theme --background 1 aurora
assert_eq "--background still picks exactly that one" "1-aurora.jpg" "$(showing)"
set_theme boreal
set_theme aurora
assert_eq "the newer pick is the one remembered" "1-aurora.jpg" "$(showing)"
mock_cleanup

# --- a remembered background that's gone: the first, as before ---
setup
set_theme --background 3 aurora
set_theme boreal
rm "$STOCK/aurora/backgrounds/3-aurora.jpg"
set_theme aurora
assert_eq "remembered background removed: the first" "1-aurora.jpg" "$(showing)"
mock_cleanup

# --- a background of the user's own for the theme ---
# (They're listed before the theme's, so these are backgrounds 1 and 2.)
setup
mkdir -p "$H/.config/ohmydebn/backgrounds/aurora"
: >"$H/.config/ohmydebn/backgrounds/aurora/a-mine.png"
: >"$H/.config/ohmydebn/backgrounds/aurora/b-mine.png"
set_theme --background 2 aurora
assert_eq "the user's own second background picked" "b-mine.png" "$(showing)"
set_theme boreal
set_theme aurora
assert_eq "the user's own background comes back too" "b-mine.png" "$(showing)"
mock_cleanup

# --- reapplying a theme (as ohmydebn-reset-config does), and a bad name ---
setup
set_theme --background 2 aurora
set_theme --keep-background aurora
assert_eq "--keep-background on the same theme keeps the picture" "2-aurora.jpg" "$(showing)"
assert_eq "reapplying the same theme records nothing for it" "no" "$(exists "$MEMORY/aurora")"
echo "../../escape" >"$H/.config/ohmydebn/current/theme.name"
set_theme aurora
assert_eq "a theme.name that walks out of the folder writes nothing there" "no" "$(exists "$H/.local/state/escape")"
assert_eq "...or anywhere under the memory folder" "" "$(find "$MEMORY" -name '*escape*' 2>/dev/null)"
mock_cleanup

# --- the carousel starts on the same background ---
setup
set_theme --background 3 aurora
set_theme --background 2 boreal
carousel_index() {
  HOME="$H" python3 - "$REPO_ROOT/bin/ohmydebn-theme-carousel" "$1" "$STOCK" <<'PY'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("carousel", sys.argv[1])
spec = importlib.util.spec_from_loader("carousel", loader)
carousel = importlib.util.module_from_spec(spec)
loader.exec_module(carousel)
slug, stock = sys.argv[2], sys.argv[3]
backgrounds = sorted(os.path.join(stock, slug, "backgrounds", f) for f in os.listdir(os.path.join(stock, slug, "backgrounds")))
print(carousel.starting_background_index(slug, backgrounds) + 1)
PY
}
assert_eq "carousel, the applied theme: the live background" "2" "$(carousel_index boreal)"
assert_eq "carousel, another theme: the background it last had" "3" "$(carousel_index aurora)"
rm -f "$MEMORY/aurora"
assert_eq "carousel, nothing remembered: the first" "1" "$(carousel_index aurora)"
mock_cleanup

test_summary
