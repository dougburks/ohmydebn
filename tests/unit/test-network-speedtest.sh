#!/bin/bash
#
# Unit tests for bin/ohmydebn-network-speedtest's endpoint fetch. It gives
# curl a time limit (a stalled connection used to hang at "Fetching speed
# test endpoints..." for good) and hands the URLs to the workers as a
# quoted list (they carry ? and &, and an unquoted list globs). ip, curl
# and the worker are stand-ins, the run is cut to one second and one
# worker, and the loopback interface's counters are read.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-network-speedtest ==="

mock_init
mock_bin ip <<'STUB'
#!/bin/bash
echo "1.1.1.1 dev lo src 127.0.0.1"
STUB
mock_bin curl <<'STUB'
#!/bin/bash
mock_log "curl $*"
echo '{"targets":[{"url":"https://example.com/*?a=1&b=2"}]}'
STUB
mock_bin ohmydebn-network-speedtest-worker <<'STUB'
#!/bin/bash
mock_log "worker $1 args=$# url=$2"
STUB
sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e 's/^duration=.*/duration=1/' -e 's/^parallel=.*/parallel=1/' \
  "$REPO_ROOT/bin/ohmydebn-network-speedtest" >"$MOCK_DIR/speedtest"

# A directory a glob of that URL would match, in the directory it runs from.
mkdir -p "$MOCK_DIR/cwd/https:/example.com/xya=1&b=2"
# A shell left waiting on stdin would hang here: the run used to end in
# `exec bash`, from when it had a window of its own.
mkfifo "$MOCK_DIR/tty"
exec 3<>"$MOCK_DIR/tty"
OUTPUT=$(cd "$MOCK_DIR/cwd" && PATH="$(mock_path)" timeout 20 bash "$MOCK_DIR/speedtest" <&3 2>&1)
STATUS=$?
exec 3<&-
CALLS=$(cat "$MOCK_CALLS")
assert_eq "ends by itself, without a nested shell" "0" "$STATUS"
assert_contains "says it's done" "$OUTPUT" "Speed test complete."
assert_contains "the endpoint fetch has a time limit" "$CALLS" "curl -fsS --max-time"
assert_contains "the worker gets the URL exactly, not globbed" "$CALLS" "worker down args=2 url=https://example.com/*?a=1&b=2"

mock_cleanup
test_summary
