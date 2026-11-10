#!/bin/bash
#
# Unit tests for bin/ohmydebn-ssh-server (the menu launcher). Without
# systemd its status window ran a bare `service ssh status`, and service is
# in /usr/sbin, off a normal user's PATH on Devuan and LCOS, so the window
# said "service: command not found" instead of the status. dpkg answers
# from MOCK_INSTALLED; the floating-terminal launchers only log their
# arguments.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-ssh-server ==="

setup() {
  mock_init
  mock_bin dpkg <<'STUB'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]]
STUB
  mock_bin hostname <<'STUB'
#!/bin/bash
echo "192.0.2.10 fd00::10"
STUB
  for name in ohmydebn-launch-floating-terminal ohmydebn-launch-floating-terminal-with-presentation; do
    mock_bin "$name" <<STUB
#!/bin/bash
echo "$name \$*" >>"\$MOCK_CALLS"
STUB
  done
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-ssh-server" >"$MOCK_DIR/ssh-server"
}
run() {
  USER=doug PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" bash "$MOCK_DIR/ssh-server" </dev/null >/dev/null 2>&1
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

setup
MOCK_INSTALLED="" run
assert_contains "not installed: installer presented" "$CALLS" "ohmydebn-launch-floating-terminal-with-presentation SSH Server $MOCK_BIN/ohmydebn-ssh-server-install"
mock_cleanup

setup
MOCK_INSTALLED="openssh-server" run
assert_eq "installed: exits 0" "0" "$STATUS"
assert_not_contains "installed: no installer" "$CALLS" "with-presentation"
assert_contains "installed: status window with the address" "$CALLS" "ssh doug@192.0.2.10"
assert_contains "installed: without systemd, service is called by its full path" "$CALLS" "else /usr/sbin/service ssh status; fi"
assert_contains "installed: firewall hint included" "$CALLS" "ohmydebn-firewall-hint 22 'SSH Server'"
mock_cleanup

test_summary
