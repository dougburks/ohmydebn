#!/bin/bash
#
# Unit tests for bin/ohmydebn-opencode-install. Like every other installer,
# it does nothing to the packages when OpenCode is already installed: it
# used to run apt update and apt install on every run. sudo and dpkg are
# stand-ins; HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-opencode-install ==="

# setup <dpkg -s exit status: 0 installed, 1 not>
setup() {
  mock_init
  mkdir -p "$MOCK_DIR/home"
  mock_bin dpkg <<STUB
#!/bin/bash
exit $1
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
STUB
  mock_bin ohmydebn-ai-set-default <<'STUB'
#!/bin/bash
mock_log "ai-set-default $*"
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-opencode-install" >"$MOCK_DIR/install"
}
run() { HOME="$MOCK_DIR/home" PATH="$(mock_path)" bash "$MOCK_DIR/install" --skip-prompt </dev/null >/dev/null 2>&1; STATUS=$?; }

setup 0
run
assert_eq "already installed: exits 0" "0" "$STATUS"
assert_not_contains "already installed: apt isn't run" "$(cat "$MOCK_CALLS")" "apt"
mock_cleanup

setup 1
run
assert_contains "not installed: apt update first" "$(head -1 "$MOCK_CALLS")" "sudo /usr/bin/apt update"
assert_contains "not installed: then installs it" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y install ohmydebn-opencode-cli"
mock_cleanup

test_summary
