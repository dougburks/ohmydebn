#!/bin/bash
#
# Unit tests for bin/ohmydebn-power - the init-agnostic suspend/reboot/
# poweroff wrapper the System menu calls. The System menu used to call
# systemctl directly, which fails outright on Devuan (no systemd); elogind's
# loginctl has the same three verbs there, but systemd's loginctl does not,
# so the wrapper must branch on the running init, not on which binary is
# present. Both systemctl and loginctl are mocked so nothing here can
# actually power anything off.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-power"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-power ==="

setup_mocks() {
  mock_bin systemctl <<'EOF2'
#!/bin/bash
mock_log "systemctl $*"
exit 0
EOF2
  mock_bin loginctl <<'EOF2'
#!/bin/bash
mock_log "loginctl $*"
exit 0
EOF2
}

# run_case <description> <systemd present: yes|no> <action> <expected call>
run_case() {
  local desc="$1" has_systemd="$2" action="$3" expected="$4"
  mock_init
  setup_mocks
  local sd_dir="$MOCK_DIR/systemd-dir"
  [[ "$has_systemd" == "yes" ]] && mkdir -p "$sd_dir"
  OHMYDEBN_TEST_SYSTEMD_DIR="$sd_dir" PATH="$(mock_path)" bash "$SCRIPT" "$action" >/dev/null 2>&1
  local exit_code=$?
  assert_eq "$desc: exits 0" "0" "$exit_code"
  assert_eq "$desc: exactly one call, the right one" "$expected" "$(cat "$MOCK_CALLS")"
  mock_cleanup
}

run_case "systemd: suspend" yes suspend "systemctl suspend"
run_case "systemd: reboot" yes reboot "systemctl reboot"
run_case "systemd: poweroff" yes poweroff "systemctl poweroff"
run_case "no systemd (Devuan/elogind): suspend" no suspend "loginctl suspend"
run_case "no systemd (Devuan/elogind): reboot" no reboot "loginctl reboot"
run_case "no systemd (Devuan/elogind): poweroff" no poweroff "loginctl poweroff"

# Unknown/missing action: refuse rather than pass garbage to the init system
mock_init
setup_mocks
mkdir -p "$MOCK_DIR/systemd-dir"
OUTPUT=$(OHMYDEBN_TEST_SYSTEMD_DIR="$MOCK_DIR/systemd-dir" PATH="$(mock_path)" bash "$SCRIPT" halt 2>&1)
EXIT_CODE=$?
assert_eq "unknown action: non-zero exit" "1" "$EXIT_CODE"
assert_contains "unknown action: usage shown" "$OUTPUT" "Usage:"
assert_eq "unknown action: nothing called" "" "$(cat "$MOCK_CALLS")"
OUTPUT=$(OHMYDEBN_TEST_SYSTEMD_DIR="$MOCK_DIR/systemd-dir" PATH="$(mock_path)" bash "$SCRIPT" 2>&1)
EXIT_CODE=$?
assert_eq "no action: non-zero exit" "1" "$EXIT_CODE"
mock_cleanup

test_summary
