#!/bin/bash
#
# Unit tests for bin/ohmydebn-gestures-install and
# bin/ohmydebn-localsend-install. Both used to run apt update and apt
# install even when their app was already installed (only the prompt was
# skipped), so running one again asked for a sudo password and
# refreshed apt for nothing. Now an installed app means nothing is run.
#
# sudo is mocked to only log, and dpkg answers from MOCK_INSTALLED.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-gestures-install / bin/ohmydebn-localsend-install ==="

setup() {
  mock_init
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF2
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
}

# <script> <package> <what apt installs>
for case in "gestures:touchegg:touchegg libpugixml1v5" "localsend:localsend:localsend gir1.2-ayatanaappindicator3-0.1"; do
  IFS=: read -r name package installs <<<"$case"
  SCRIPT="$REPO_ROOT/bin/ohmydebn-$name-install"

  setup
  OUT=$(MOCK_INSTALLED="" PATH="$(mock_path)" bash "$SCRIPT" <<<"" 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
  assert_eq "$name, not installed: succeeds" "0" "$STATUS"
  assert_contains "$name, not installed: asks first" "$OUT" "Press Enter to continue or Ctrl-C to cancel."
  assert_contains "$name, not installed: refreshes apt" "$CALLS" "sudo /usr/bin/apt update"
  assert_contains "$name, not installed: installs it" "$CALLS" "sudo /usr/bin/apt -y install $installs"
  mock_cleanup

  setup
  OUT=$(MOCK_INSTALLED="$package" PATH="$(mock_path)" bash "$SCRIPT" </dev/null 2>&1)
  STATUS=$?
  assert_eq "$name, installed: succeeds" "0" "$STATUS"
  assert_eq "$name, installed: nothing run" "" "$(cat "$MOCK_CALLS")"
  assert_eq "$name, installed: nothing said" "" "$OUT"
  mock_cleanup
done

test_summary
