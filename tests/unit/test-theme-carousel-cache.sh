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
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
echo "ohmydebn-headline $*" >>"$MOCK_CALLS"
EOF2
  # --warm-cache-pending answers from MOCK_PENDING (the number of images
  # not yet cached); --warm-cache is only logged.
  mock_bin ohmydebn-theme-carousel <<'EOF2'
#!/bin/bash
echo "ohmydebn-theme-carousel $*" >>"$MOCK_CALLS"
[[ "$1" == --warm-cache-pending ]] && echo "${MOCK_PENDING:-0}"
exit 0
EOF2
  # setsid/nice/ionice are real (they're in the PATH as usual) and just
  # exec through to the mocked carousel, which records how it was called.
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/patched.sh"
}

setup
MOCK_PENDING=372 DISPLAY=:0 PATH="$(mock_path)" bash "$MOCK_DIR/patched.sh" </dev/null >/dev/null 2>&1
sleep 0.5
CALLS=$(cat "$MOCK_CALLS")
assert_contains "images missing: headline names the count" "$CALLS" "ohmydebn-headline Preparing 372 theme previews in the background"
assert_eq "images missing: carousel run in warm-cache mode, once" "1" "$(grep -cx 'ohmydebn-theme-carousel --warm-cache' "$MOCK_CALLS")"
mock_cleanup

# The usual ohmydebn-update on an unchanged system: nothing missing, so
# no headline and no warm-up - only the (cheap) count.
setup
MOCK_PENDING=0 DISPLAY=:0 PATH="$(mock_path)" bash "$MOCK_DIR/patched.sh" </dev/null >/dev/null 2>&1
sleep 0.3
assert_eq "nothing missing: only the pending count is asked for" "ohmydebn-theme-carousel --warm-cache-pending" "$(cat "$MOCK_CALLS")"
mock_cleanup

setup
env -u DISPLAY PATH="$(mock_path)" bash "$MOCK_DIR/patched.sh" </dev/null >/dev/null 2>&1
sleep 0.3
assert_eq "no display: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

test_summary
