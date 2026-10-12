#!/bin/bash
#
# Unit tests for bin/ohmydebn-demo. A key stops only the demo's own ttfx:
# it used to run `pkill -x ttfx`, which also stopped the animation in an
# open logo window, plus a `pkill -f` whose pattern never matched. ttfx is
# a stand-in script named ttfx (so `pkill -x ttfx` would match it too).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-demo ==="

mock_init
# A real process named ttfx: a copy of sleep under that name.
mkdir -p "$MOCK_DIR/real"
cp "$(command -v sleep)" "$MOCK_DIR/real/ttfx"
mock_bin ttfx <<'STUB'
#!/bin/bash
mock_log "ttfx started"
exec "$MOCK_DIR/real/ttfx" 30
STUB
mock_bin tput <<'STUB'
#!/bin/bash
echo 40
STUB
sed -e "s#/usr/bin/ttfx#$MOCK_BIN/ttfx#g" -e "s#^sleep 0.6#sleep 0#" "$REPO_ROOT/bin/ohmydebn-demo" >"$MOCK_DIR/demo"

# Another window's ttfx (the logo's), already running.
"$MOCK_BIN/ttfx" &
OTHER=$!
sleep 0.3

# The demo, with a key pressed half a second in.
(sleep 0.5; echo x) | PATH="$(mock_path)" timeout 10 bash "$MOCK_DIR/demo" >/dev/null 2>&1
STATUS=$?
sleep 0.3
assert_eq "a key ends the demo" "0" "$STATUS"
assert_eq "the demo's own ttfx was started" "2" "$(grep -c 'ttfx started' "$MOCK_CALLS")"
assert_eq "another window's ttfx keeps running" "yes" "$(kill -0 "$OTHER" 2>/dev/null && echo yes || echo no)"
assert_eq "the demo's own ttfx is stopped: only the other one is left" "1" "$(pgrep -f "$MOCK_DIR/real/ttfx" | wc -l)"

pkill -f "$MOCK_DIR/real/ttfx" 2>/dev/null
wait "$OTHER" 2>/dev/null
mock_cleanup
test_summary
