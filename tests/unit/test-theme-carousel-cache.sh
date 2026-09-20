#!/bin/bash
#
# Unit tests for install/finalization/theme-carousel-cache.sh: the
# background warm-up of ohmydebn-theme-carousel's disk cache. It must run
# the carousel's --warm-cache mode detached at low priority when there is
# a display, and do nothing at all without one (headless install/CI).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/finalization/theme-carousel-cache.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/finalization/theme-carousel-cache.sh ==="

setup() {
  mock_init
  for name in ohmydebn-headline ohmydebn-theme-carousel; do
    mock_bin "$name" <<EOF2
#!/bin/bash
echo "$name \$*" >>"\$MOCK_CALLS"
EOF2
  done
  # setsid/nice/ionice are real (they're in the PATH as usual) and just
  # exec through to the mocked carousel, which records how it was called.
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/patched.sh"
}

setup
DISPLAY=:0 PATH="$(mock_path)" bash "$MOCK_DIR/patched.sh" </dev/null >/dev/null 2>&1
sleep 0.5
CALLS=$(cat "$MOCK_CALLS")
assert_contains "with a display: headline shown" "$CALLS" "ohmydebn-headline Preparing theme previews in the background"
assert_contains "with a display: carousel run in warm-cache mode" "$CALLS" "ohmydebn-theme-carousel --warm-cache"
mock_cleanup

setup
env -u DISPLAY PATH="$(mock_path)" bash "$MOCK_DIR/patched.sh" </dev/null >/dev/null 2>&1
sleep 0.3
assert_eq "no display: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

test_summary
