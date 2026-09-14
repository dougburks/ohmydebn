#!/bin/bash
#
# Unit tests for bin/ohmydebn-google-chrome-stable-remove and
# bin/ohmydebn-code-remove - the two remove scripts whose apt source file
# is self-registered by the vendor's OWN postinst (Chrome, VS Code) rather
# than written by ohmydebn. Mocks dpkg/sudo so nothing here touches the
# real system.
#
# Regression: Chrome's postinst switched from google-chrome.list to
# google-chrome.sources (deb822), so the old rm-source-then-apt-update
# order left the live .sources file pointing at a keyring the script had
# just deleted - every run then spewed a "sqv failed to parse keyring"
# warning from apt update. The fix is to purge FIRST (letting the vendor's
# maintainer scripts clean up the source file they created), rm leftovers
# by every known filename, and apt update LAST.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

# assert_order <desc>: asserts that the two lines matching the two given
# substrings both appear in $MOCK_CALLS, in that order.
assert_order() {
  local desc="$1" first="$2" second="$3"
  local n1 n2
  n1=$(grep -n -F -m1 "$first" "$MOCK_CALLS" | cut -d: -f1)
  n2=$(grep -n -F -m1 "$second" "$MOCK_CALLS" | cut -d: -f1)
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ -n "$n1" && -n "$n2" && "$n1" -lt "$n2" ]]; then
    echo "  ok - $desc"
  else
    echo "  FAIL - $desc"
    echo "    expected '$first' (line ${n1:-missing}) before '$second' (line ${n2:-missing})"
    echo "    calls: $(cat "$MOCK_CALLS")"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# run_remove <script> <installed-pkg>: runs <script> with --skip-prompt
# against mocks where dpkg -s reports <installed-pkg> as installed and
# sudo logs every call to $MOCK_CALLS.
run_remove() {
  local script="$1" pkg="$2"
  mock_bin dpkg <<EOF
#!/bin/bash
[[ "\$1" == "-s" && "\$2" == "$pkg" ]] && exit 0
exit 1
EOF
  mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "$*"
exit 0
EOF
  PATH="$(mock_path)" bash "$script" --skip-prompt </dev/null >/dev/null 2>&1
}

for entry in \
  "google-chrome-stable-remove:google-chrome-stable:google-chrome" \
  "code-remove:code:vscode"; do
  IFS=: read -r name pkg srcbase <<<"$entry"
  SCRIPT="$REPO_ROOT/bin/ohmydebn-$name"

  echo "=== ohmydebn-$name ==="

  # Scenario 1: installed -> purge runs BEFORE any repo-file cleanup (so
  # the vendor's own maintainer scripts remove the source file while its
  # keyring still exists), leftovers are rm'd under BOTH the legacy .list
  # and current .sources names, and apt update runs only after all of that.
  mock_init
  run_remove "$SCRIPT" "$pkg"
  CALLS=$(cat "$MOCK_CALLS")
  assert_order "purge before repo-file cleanup" "purge $pkg" "rm -f /etc/apt/sources.list.d/$srcbase"
  assert_contains "legacy .list leftover removed" "$CALLS" "/etc/apt/sources.list.d/$srcbase.list"
  assert_contains "deb822 .sources leftover removed" "$CALLS" "/etc/apt/sources.list.d/$srcbase.sources"
  assert_order "keyring removed before apt update" "/usr/share/keyrings/" "/usr/bin/apt update"
  assert_order "apt update after purge" "purge $pkg" "/usr/bin/apt update"
  mock_cleanup

  # Scenario 2: not installed -> no sudo activity at all
  mock_init
  run_remove "$SCRIPT" "some-other-package"
  assert_eq "not installed: nothing invoked via sudo" "" "$(cat "$MOCK_CALLS")"
  mock_cleanup
done

test_summary
