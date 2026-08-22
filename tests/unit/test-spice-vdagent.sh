#!/bin/bash
#
# Unit tests for install/packaging/spice-vdagent.sh. Verifies the
# spice-channel gate added around the install+pin block: it must only run
# when the com.redhat.spice.0 virtio-serial channel is present, and the
# once-only state file must still short-circuit every future run
# regardless of channel presence. The real /dev path can't be faked into
# existing/not existing without root, so OHMYDEBN_TEST_SPICE_CHANNEL (see
# the script itself) swaps in a scratch path instead.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/packaging/spice-vdagent.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/packaging/spice-vdagent.sh ==="

setup_mocks() {
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
echo "ohmydebn-headline $*" >>"$MOCK_CALLS"
EOF
  mock_bin sudo <<'EOF'
#!/bin/bash
echo "sudo $*" >>"$MOCK_CALLS"
exit 0
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/spice-vdagent-patched.sh"
}

# Scenario 1: no spice channel -> install/pin skipped entirely, state file
# still written so this doesn't re-run on every future install.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
HOME="$SCRATCH_HOME" OHMYDEBN_TEST_SPICE_CHANNEL="$MOCK_DIR/no-such-channel" \
  PATH="$(mock_path)" bash "$MOCK_DIR/spice-vdagent-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "no channel: apt install never called" "$CALLS" "install spice-vdagent"
assert_not_contains "no channel: preferences pin never written" "$CALLS" "preferences.d/ohmydebn-spice-vdagent"
assert_eq "no channel: state file written so this doesn't re-run" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/spice-vdagent-20260803" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: spice channel present -> install + version pin both happen
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
touch "$MOCK_DIR/fake-spice-channel"
HOME="$SCRATCH_HOME" OHMYDEBN_TEST_SPICE_CHANNEL="$MOCK_DIR/fake-spice-channel" \
  PATH="$(mock_path)" bash "$MOCK_DIR/spice-vdagent-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "channel present: apt installs the pinned version" "$CALLS" "install spice-vdagent=0.22.1-4.1"
assert_contains "channel present: preferences pin gets written" "$CALLS" "tee /etc/apt/preferences.d/ohmydebn-spice-vdagent"
assert_contains "channel present: headline printed" "$CALLS" "ohmydebn-headline"
assert_eq "channel present: state file written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/spice-vdagent-20260803" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: state file already exists -> nothing runs at all, even with
# the channel present (the once-only outer gate still wins, unchanged)
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/spice-vdagent-20260803"
touch "$MOCK_DIR/fake-spice-channel"
HOME="$SCRATCH_HOME" OHMYDEBN_TEST_SPICE_CHANNEL="$MOCK_DIR/fake-spice-channel" \
  PATH="$(mock_path)" bash "$MOCK_DIR/spice-vdagent-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_eq "already ran: nothing called at all" "" "$CALLS"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
