#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-vscode with a theme whose
# vscode.json leaves out a key. jq -r printed a missing key as the string
# "null", so the hook ran `code --install-extension null` and set the color
# theme to "null". The editor is a stand-in that logs its arguments; HOME
# is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-vscode ==="

setup() {
  mock_init
  H="$MOCK_DIR/home"
  mkdir -p "$H/.config/ohmydebn/current/theme" "$H/.config/Code/User"
  printf '%s\n' "$1" >"$H/.config/ohmydebn/current/theme/vscode.json"
  printf '{\n  "editor.fontSize": 14\n}\n' >"$H/.config/Code/User/settings.json"
  mock_bin code <<'STUB'
#!/bin/bash
mock_log "code $*"
STUB
  mock_bin ohmydebn-cmd-present <<'STUB'
#!/bin/bash
exit 0
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-theme-set-vscode" >"$MOCK_DIR/hook"
}
run() { HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/hook" </dev/null >/dev/null 2>&1; }
setting() { jq -r '.["workbench.colorTheme"] // "<unset>"' "$H/.config/Code/User/settings.json"; }

setup '{"name": "Tokyo Night"}'
run
assert_not_contains "no extension key: nothing installed" "$(cat "$MOCK_CALLS")" "--install-extension"
assert_eq "no extension key: the theme is still set" "Tokyo Night" "$(setting)"
mock_cleanup

setup '{"name": "Nord", "extension": "arcticicestudio.nord-visual-studio-code"}'
run
assert_contains "both keys: the extension is installed" "$(cat "$MOCK_CALLS")" "--install-extension arcticicestudio.nord-visual-studio-code"
assert_eq "both keys: the theme is set" "Nord" "$(setting)"
mock_cleanup

test_summary
