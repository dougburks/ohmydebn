#!/bin/bash
#
# Unit tests for first_background() in bin/ohmydebn-theme-carousel: the
# image the carousel shows for a theme it has no background list for, and
# lands on when there is none. It picked only .png and .jpg files, so a
# theme whose backgrounds are all .webp (every Omarchy theme from 4.5 on)
# fell back to its preview, or to nothing. HOME is a scratch directory, and
# the function is called from the carousel's own code.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-carousel: first_background ==="

mock_init
H="$MOCK_DIR/home"
THEMES="$H/.config/ohmydebn/themes"

# first_background(<slug>), from the carousel itself (theme_dir looks in
# the user's themes folder first, which is where these are).
first_background() {
  HOME="$H" python3 - "$REPO_ROOT/bin/ohmydebn-theme-carousel" "$1" <<'PY'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("carousel", sys.argv[1])
spec = importlib.util.spec_from_loader("carousel", loader)
carousel = importlib.util.module_from_spec(spec)
loader.exec_module(carousel)
path = carousel.first_background(sys.argv[2])
print(os.path.basename(path) if path else "")
PY
}

mkdir -p "$THEMES/webp-only/backgrounds"
: >"$THEMES/webp-only/backgrounds/1-starbase.webp"
: >"$THEMES/webp-only/backgrounds/2-dawn.WEBP"
assert_eq "WebP-only theme: its first background" "1-starbase.webp" "$(first_background webp-only)" </dev/null

mkdir -p "$THEMES/mixed/backgrounds"
: >"$THEMES/mixed/backgrounds/2-lake.jpg"
: >"$THEMES/mixed/backgrounds/1-cosmic.webp"
assert_eq "mixed theme: the first by name, WebP or not" "1-cosmic.webp" "$(first_background mixed)" </dev/null

mkdir -p "$THEMES/upper/backgrounds"
: >"$THEMES/upper/backgrounds/Dawn.WEBP"
assert_eq "an upper-case .WEBP counts too" "Dawn.WEBP" "$(first_background upper)" </dev/null

mkdir -p "$THEMES/not-images/backgrounds/intros"
: >"$THEMES/not-images/backgrounds/README.md"
: >"$THEMES/not-images/backgrounds/intros/1-a.webm"
assert_eq "no image: nothing (not a README or an intros folder)" "" "$(first_background not-images)" </dev/null

mock_cleanup
test_summary
