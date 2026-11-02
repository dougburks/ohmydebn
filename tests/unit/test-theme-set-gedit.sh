#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-gedit: on a theme switch it flips
# gedit's theme-variant to another value and back, so a running gedit
# reloads its colors, and leaves it at the value it had. It used to always
# end on 'light', so a user's 'system' or 'dark' was lost at every switch.
# gsettings is a stand-in that keeps the one key in a file.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-gedit ==="

# run <stored value, or "" for gedit without the key>
run() {
  mock_init
  [ -n "$1" ] && echo "$1" >"$MOCK_DIR/variant"
  mock_bin gsettings <<'STUB'
#!/bin/bash
mock_log "gsettings $*"
[ -f "$MOCK_DIR/variant" ] || exit 1
case "$1" in
get) cat "$MOCK_DIR/variant" ;;
set) echo "$4" >"$MOCK_DIR/variant" ;;
esac
STUB
  PATH="$(mock_path)" bash "$REPO_ROOT/bin/ohmydebn-theme-set-gedit" </dev/null >/dev/null 2>&1
  STATUS=$?
  SETS=$(grep -c 'gsettings set' "$MOCK_CALLS")
}

for variant in "'light'" "'dark'" "'system'"; do
  run "$variant"
  assert_eq "$variant: exits 0" "0" "$STATUS"
  assert_eq "$variant: left as it was" "$variant" "$(cat "$MOCK_DIR/variant")"
  assert_eq "$variant: flipped and back, so gedit reloads" "2" "$SETS"
  mock_cleanup
done

run ""
assert_eq "no theme-variant key (gedit before 47): exits 0" "0" "$STATUS"
assert_eq "no theme-variant key: nothing set" "0" "$SETS"
mock_cleanup

test_summary
