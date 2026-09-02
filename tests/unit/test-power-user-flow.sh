#!/bin/bash
#
# Unit tests for install/packaging/power-user.sh. Verifies the $POWER_USER
# export (set by install.sh, consumed here after dependencies.sh has
# already run - see the comment in power-user.sh for why the order
# matters) correctly gates the whole block, and that every expected
# sub-script gets invoked with --skip-prompt. All of power-user.sh's
# target scripts are hardcoded to /usr/share/ohmydebn/bin/..., so this
# patches a copy to point at the mock bin dir instead.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/packaging/power-user.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/packaging/power-user.sh ==="

setup_mocks() {
  for name in ohmydebn-pkg-remove-all-optional ohmydebn-virtmanager-install \
    ohmydebn-brave-origin-install ohmydebn-gimp-install \
    ohmydebn-podman-install ohmydebn-pkg-install-optional \
    ohmydebn-magnifier-enable; do
    mock_bin "$name" <<EOF
#!/bin/bash
echo "$name \$*" >> "\$MOCK_CALLS"
EOF
  done
  mock_bin sudo <<'EOF'
#!/bin/bash
echo "sudo $*" >>"$MOCK_CALLS"
exit 0
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/power-user-patched.sh"
}

# Scenario 1: POWER_USER not set (default install.sh behavior) -> no-op
mock_init
setup_mocks
PATH="$(mock_path)" bash "$MOCK_DIR/power-user-patched.sh" >/dev/null 2>&1
assert_eq "default: nothing called when POWER_USER is unset" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# Scenario 2: POWER_USER=false explicitly -> still a no-op
mock_init
setup_mocks
POWER_USER=false PATH="$(mock_path)" bash "$MOCK_DIR/power-user-patched.sh" >/dev/null 2>&1
assert_eq "POWER_USER=false: nothing called" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# Scenario 3: POWER_USER=true -> removal + every extra install script + magnifier
mock_init
setup_mocks
POWER_USER=true PATH="$(mock_path)" bash "$MOCK_DIR/power-user-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "POWER_USER=true: removal runs with --skip-prompt" "$CALLS" "ohmydebn-pkg-remove-all-optional --skip-prompt"
for name in ohmydebn-virtmanager-install ohmydebn-brave-origin-install \
  ohmydebn-gimp-install ohmydebn-podman-install; do
  assert_contains "POWER_USER=true: $name runs with --skip-prompt" "$CALLS" "$name --skip-prompt"
done
assert_not_contains "POWER_USER=true: claude-code is not installed" "$CALLS" "ohmydebn-claude-code-install"
assert_not_contains "POWER_USER=true: opencode is not installed" "$CALLS" "ohmydebn-opencode-install"
assert_contains "POWER_USER=true: keepassxc-minimal/rclone/etc batch install runs" "$CALLS" "ohmydebn-pkg-install-optional keepassxc-minimal"
assert_contains "POWER_USER=true: magnifier gets enabled" "$CALLS" "ohmydebn-magnifier-enable"
assert_contains "POWER_USER=true: iperf3 debconf preseed happens" "$CALLS" "debconf-set-selections"
mock_cleanup

test_summary
