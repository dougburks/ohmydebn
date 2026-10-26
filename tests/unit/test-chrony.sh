#!/bin/bash
#
# Unit tests for install/config/chrony.sh: once per machine, chrony is
# turned on if it's installed but not running (or, on systemd, not
# enabled). Kali leaves it disabled at install time, so nothing kept the
# clock in sync there. sudo is a stand-in that runs mkdir/touch for real
# (inside the scratch directory) and logs the rest; dpkg, systemctl and
# pgrep answer from MOCK_* variables; the machine-wide marker and the
# systemd signal directory are pointed into the scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/chrony.sh ==="

# setup <init: systemd|sysv>
setup() {
  mock_init
  H="$MOCK_DIR/home"; mkdir -p "$H"
  SYS="$MOCK_DIR/var/lib/ohmydebn"
  SYSTEMD="$MOCK_DIR/run/systemd/system"
  [[ "$1" == systemd ]] && mkdir -p "$SYSTEMD"
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
case "$1" in mkdir | touch) "$@" ;; esac
STUB
  mock_bin ohmydebn-headline <<'STUB'
#!/bin/bash
mock_log "headline $*"
STUB
  mock_bin dpkg <<'STUB'
#!/bin/bash
[[ "$1" == "-s" && "$2" == chrony && -n "${MOCK_INSTALLED:-}" ]]
STUB
  mock_bin systemctl <<'STUB'
#!/bin/bash
[[ "$1" == is-enabled && -n "${MOCK_ENABLED:-}" ]]
STUB
  mock_bin pgrep <<'STUB'
#!/bin/bash
[[ -n "${MOCK_RUNNING:-}" ]]
STUB
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/var/lib/ohmydebn#$SYS#g" \
    "$REPO_ROOT/install/config/chrony.sh" >"$MOCK_DIR/chrony.sh"
}

run() {
  HOME="$H" PATH="$(mock_path)" OHMYDEBN_TEST_SYSTEMD_DIR="$SYSTEMD" \
    MOCK_INSTALLED="${MOCK_INSTALLED-1}" MOCK_ENABLED="${MOCK_ENABLED:-}" MOCK_RUNNING="${MOCK_RUNNING:-}" \
    bash -e -c "source '$MOCK_DIR/chrony.sh'" </dev/null >/dev/null 2>&1
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

marked() { [ -f "$SYS/chrony-enabled" ] && echo yes || echo no; }

# Kali as installed: chrony there but disabled and stopped.
setup systemd
run
assert_eq "Kali (systemd, disabled): exits 0" "0" "$STATUS"
assert_contains "Kali: chrony enabled and started" "$CALLS" "sudo systemctl enable --now chrony"
assert_eq "Kali: recorded machine-wide" "yes" "$(marked)"
mock_cleanup

# The next update: already done once, so a chrony the user turned off
# stays off.
setup systemd
mkdir -p "$SYS"; : >"$SYS/chrony-enabled"
run
assert_not_contains "already done: chrony left as the user has it" "$CALLS" "chrony"
mock_cleanup

# Every other distro: already enabled and running - nothing to do, but
# recorded so it's never checked again.
setup systemd
MOCK_ENABLED=1 MOCK_RUNNING=1 run
assert_not_contains "enabled and running: nothing changed" "$CALLS" "systemctl enable"
assert_not_contains "enabled and running: no headline" "$CALLS" "headline"
assert_eq "enabled and running: recorded" "yes" "$(marked)"
mock_cleanup

# Running but disabled: it wouldn't come back after a reboot.
setup systemd
MOCK_RUNNING=1 run
assert_contains "running but disabled: enabled" "$CALLS" "sudo systemctl enable --now chrony"
mock_cleanup

# No systemd (Devuan, MX with sysvinit): update-rc.d and service instead.
setup sysv
run
assert_contains "sysvinit, stopped: enabled with update-rc.d" "$CALLS" "sudo update-rc.d chrony enable"
assert_contains "sysvinit, stopped: started with service" "$CALLS" "sudo service chrony start"
assert_not_contains "sysvinit: no systemctl" "$CALLS" "systemctl"
assert_eq "sysvinit: recorded" "yes" "$(marked)"
mock_cleanup

setup sysv
MOCK_RUNNING=1 run
assert_not_contains "sysvinit, running: nothing changed" "$CALLS" "update-rc.d"
mock_cleanup

# chrony not installed yet (the dependencies step failed): nothing, and no
# marker, so the next run tries again.
setup systemd
MOCK_INSTALLED="" run
assert_eq "not installed: exits 0" "0" "$STATUS"
assert_not_contains "not installed: nothing run" "$CALLS" "chrony"
assert_eq "not installed: not recorded, so it's tried again" "no" "$(marked)"
mock_cleanup

test_summary
