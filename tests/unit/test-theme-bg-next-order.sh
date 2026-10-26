#!/bin/bash
#
# Unit tests for the order bin/ohmydebn-theme-bg-next numbers backgrounds
# in. The theme carousel previews its N-th background and applies it with
# `--background N`, so both must sort the same way. The carousel sorts by
# codepoint; bg-next sorted by locale, so with mixed-case names
# ("Beach.jpg", "aurora.jpg") it applied a different wallpaper than the one
# shown. Each run here is checked against the carousel's own
# list_backgrounds_for_theme. HOME is a scratch directory and
# ohmydebn-theme-bg-set is a stand-in that logs what it was given.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-bg-next: background order ==="

mock_init
H="$MOCK_DIR/home"
SLUG=mytheme
mkdir -p "$H/.config/ohmydebn/themes/$SLUG/backgrounds" "$H/.config/ohmydebn/current"
for name in Beach.jpg aurora.jpg _lake.png 2-hills.jpg; do
  : >"$H/.config/ohmydebn/themes/$SLUG/backgrounds/$name"
done
# One of the user's own for this theme, which both list too. bg-next read
# the theme's name in a way that always came back empty, so it never saw
# these, and background N was off by one from the carousel's.
mkdir -p "$H/.config/ohmydebn/backgrounds/$SLUG"
: >"$H/.config/ohmydebn/backgrounds/$SLUG/mine.png"
echo "$SLUG" >"$H/.config/ohmydebn/current/theme.name"
ln -s "$H/.config/ohmydebn/themes/$SLUG" "$H/.config/ohmydebn/current/theme"
mock_bin ohmydebn-theme-bg-set <<'STUB'
#!/bin/bash
basename "$1" >>"$MOCK_CALLS"
STUB
sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-theme-bg-next" >"$MOCK_DIR/bg-next"

# The carousel's order, from its own function (theme_dir looks in the
# user's themes folder first).
CAROUSEL=$(HOME="$H" python3 - "$REPO_ROOT/bin/ohmydebn-theme-carousel" "$SLUG" <<'PY'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("carousel", sys.argv[1])
spec = importlib.util.spec_from_loader("carousel", loader)
carousel = importlib.util.module_from_spec(spec)
loader.exec_module(carousel)
print(" ".join(os.path.basename(p) for p in carousel.list_backgrounds_for_theme(sys.argv[2])))
PY
)
BG_NEXT=""
for n in 1 2 3 4 5; do
  : >"$MOCK_CALLS"
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/bg-next" --background "$n" </dev/null >/dev/null 2>&1
  BG_NEXT+="$(cat "$MOCK_CALLS") "
done
assert_eq "the carousel's list was read" "5" "$(wc -w <<<"$CAROUSEL")"
assert_eq "background N is the carousel's N-th, whatever the locale" "$CAROUSEL" "${BG_NEXT% }"

mock_cleanup
test_summary
