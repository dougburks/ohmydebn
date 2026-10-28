#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-antigravity, which now runs the VS
# Code hook with Antigravity's binary and settings instead of being a full
# copy of it. The VS Code hook is a stand-in that logs its
# arguments.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-antigravity ==="

mock_init
mock_bin ohmydebn-theme-set-vscode <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$MOCK_CALLS"
STUB
sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-theme-set-antigravity" >"$MOCK_DIR/hook"
HOME=/home/someone bash "$MOCK_DIR/hook" </dev/null
STATUS=$?
assert_eq "exits with the VS Code hook's status" "0" "$STATUS"
assert_eq "runs the VS Code hook with Antigravity's binary and settings" "/usr/share/antigravity/bin/antigravity
/home/someone/.config/Antigravity/User/settings.json" "$(cat "$MOCK_CALLS")"

mock_cleanup
test_summary
