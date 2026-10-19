#!/bin/bash
#
# Unit tests for bin/ohmydebn-tailscale-install. It ran
# `apt update && apt install`, so under set -e a failed update skipped the
# install without stopping the script, which went on to configure a
# tailscale that wasn't there. sudo, dpkg and curl are stand-ins.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-tailscale-install ==="

setup() {
  mock_init
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 1
STUB
  mock_bin curl <<'STUB'
#!/bin/bash
echo "deb https://pkgs.tailscale.com/stable/debian trixie main"
STUB
  # Logs every privileged call; MOCK_UPDATE_FAILS makes apt update fail.
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
case "$*" in
*tee*) cat >/dev/null ;;
"/usr/bin/apt update") [ -z "${MOCK_UPDATE_FAILS:-}" ] || exit 100 ;;
esac
exit 0
STUB
}
run() {
  PATH="$(mock_path)" bash "$REPO_ROOT/bin/ohmydebn-tailscale-install" <<<"" >/dev/null 2>&1
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

setup
run
assert_eq "installs: exits 0" "0" "$STATUS"
assert_contains "installs tailscale" "$CALLS" "sudo /usr/bin/apt -y install tailscale"
assert_contains "then makes the user its operator" "$CALLS" "sudo /usr/bin/tailscale set --operator=$USER"
mock_cleanup

setup
MOCK_UPDATE_FAILS=1 run
assert_eq "apt update fails: fails" "100" "$STATUS"
assert_not_contains "apt update fails: nothing installed" "$CALLS" "apt -y install"
assert_not_contains "apt update fails: nothing configured" "$CALLS" "tailscale set"
mock_cleanup

test_summary
