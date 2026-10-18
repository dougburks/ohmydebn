#!/bin/bash
#
# Unit tests for bin/ohmydebn-apt-pins: --list is the doctor's list of
# third-party repos and their pins, and --prune deletes a pin whose repo
# is gone (its app removed with Remove > Package or apt, which takes the
# repo but not OhMyDebn's pin) while never touching one whose repo is
# still there. Runs against a scratch apt dir; sudo really runs what it's
# given there.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-apt-pins"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-apt-pins ==="

setup() {
  mock_init
  APT="$MOCK_DIR/apt"
  mkdir -p "$APT/sources.list.d" "$APT/preferences.d"
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
"$@"
STUB
}
prune() { OUT=$(OHMYDEBN_TEST_APT_DIR="$APT" PATH="$(mock_path)" bash "$SCRIPT" --prune 2>&1); STATUS=$?; }
exists() { [ -e "$APT/preferences.d/$1" ] && echo yes || echo no; }

setup
for pin in claude-desktop.pref google-chrome.pref claude-code.pref chatgpt.pref brave-browser-release.pref code.pref; do
  : >"$APT/preferences.d/$pin"
done
: >"$APT/sources.list.d/claude-code.list"            # repo as .list
: >"$APT/sources.list.d/chatgpt.sources"             # repo as .sources (deb822)
: >"$APT/sources.list.d/brave-browser-release.sources" # shared by both Brave variants
: >"$APT/preferences.d/my-own.pref"                  # not OhMyDebn's
prune
assert_eq "prune: succeeds" "0" "$STATUS"
assert_eq "prune: Claude Desktop's pin goes with its repo" "no" "$(exists claude-desktop.pref)"
assert_eq "prune: Chrome's pin goes with its repo" "no" "$(exists google-chrome.pref)"
assert_eq "prune: VS Code's pin (repo vscode.list) goes too" "no" "$(exists code.pref)"
assert_contains "prune: says which pin went and why" "$OUT" "claude-desktop.pref: its repository is gone."
assert_eq "prune: a pin whose .list repo is there stays" "yes" "$(exists claude-code.pref)"
assert_eq "prune: a pin whose .sources repo is there stays" "yes" "$(exists chatgpt.pref)"
assert_eq "prune: Brave's shared pin stays while its repo is there" "yes" "$(exists brave-browser-release.pref)"
assert_eq "prune: a pin that isn't OhMyDebn's is never touched" "yes" "$(exists my-own.pref)"
# Nothing left to do: no sudo, no output.
: >"$MOCK_CALLS"
prune
assert_eq "prune again: nothing to do, nothing run" "" "$(cat "$MOCK_CALLS")"
assert_eq "prune again: says nothing" "" "$OUT"
mock_cleanup

# No preferences.d at all: fine
setup
rm -r "$APT/preferences.d"
prune
assert_eq "no preferences.d: succeeds" "0" "$STATUS"
mock_cleanup

# --list: one "repo:pin" line per pin, the ones the installers write
LIST=$(bash "$SCRIPT" --list)
assert_contains "list: Claude Desktop" "$LIST" "claude-desktop:claude-desktop.pref"
assert_contains "list: PowerShell's repo is Microsoft's" "$LIST" "microsoft-prod:powershell.pref"
bash "$SCRIPT" >/dev/null 2>&1
assert_eq "no argument: usage, exits 1" "1" "$?"

test_summary
