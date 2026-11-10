#!/bin/bash
#
# Unit tests for bin/ohmydebn-tailscale-remove. The installer now installs
# tailscale-archive-keyring too, so removal purges it, but only when it's
# installed: by purge time Tailscale's repo is gone, and apt can't locate a
# package that's neither installed nor in a repo (an older install on a
# distro with recommends off, like MX Linux). sudo and dpkg are stand-ins;
# MOCK_INSTALLED lists the packages dpkg -s reports as installed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-tailscale-remove ==="

setup() {
  mock_init
  mock_bin dpkg <<'STUB'
#!/bin/bash
[[ " ${MOCK_INSTALLED:-} " == *" ${!#} "* ]]
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
exit 0
STUB
}
run() {
  PATH="$(mock_path)" bash "$REPO_ROOT/bin/ohmydebn-tailscale-remove" --skip-prompt </dev/null >/dev/null 2>&1
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

setup
MOCK_INSTALLED="tailscale tailscale-archive-keyring" run
assert_eq "both installed: exits 0" "0" "$STATUS"
assert_contains "both installed: purges both" "$CALLS" "sudo /usr/bin/apt -y purge tailscale tailscale-archive-keyring"
assert_contains "both installed: removes the pin" "$CALLS" "sudo rm -f /etc/apt/preferences.d/tailscale.pref"
mock_cleanup

setup
MOCK_INSTALLED="tailscale" run
assert_eq "no keyring package: exits 0" "0" "$STATUS"
assert_contains "no keyring package: purges tailscale" "$CALLS" "sudo /usr/bin/apt -y purge tailscale"
assert_not_contains "no keyring package: doesn't name it" "$CALLS" "purge tailscale tailscale-archive-keyring"
mock_cleanup

setup
MOCK_INSTALLED="" run
assert_eq "not installed: exits 0" "0" "$STATUS"
assert_not_contains "not installed: purges nothing" "$CALLS" "purge"
mock_cleanup

test_summary
