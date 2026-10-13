#!/bin/bash
#
# Unit tests for install/config/ufw.sh. The firewall is set up once per
# machine: it used to be recorded only in each user's home, so a second
# user's first install or update turned the firewall back on even if
# someone had turned it off. Now a machine-wide marker records it, and a
# user's old marker counts as "already set up". sudo is a stand-in that
# runs mkdir/touch for real (inside the scratch directory) and logs the
# rest; the machine-wide path is pointed into the scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/ufw.sh ==="

# setup <user marker: yes/no> <machine marker: yes/no>
setup() {
  mock_init
  H="$MOCK_DIR/home"
  SYS="$MOCK_DIR/var/lib/ohmydebn"
  mkdir -p "$H/.local/state"
  [[ "$1" == yes ]] && : >"$H/.local/state/ohmydebn-ufw"
  if [[ "$2" == yes ]]; then
    mkdir -p "$SYS"
    : >"$SYS/ufw-configured"
  fi
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
case "$1" in mkdir | touch) "$@" ;; esac
STUB
  mock_bin ohmydebn-headline <<'STUB'
#!/bin/bash
mock_log "headline $*"
STUB
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/var/lib/ohmydebn#$SYS#g" \
    "$REPO_ROOT/install/config/ufw.sh" >"$MOCK_DIR/ufw.sh"
}

run() {
  HOME="$H" PATH="$(mock_path)" bash -e -c "source '$MOCK_DIR/ufw.sh'" </dev/null >/dev/null 2>&1
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

machine_marked() { [ -f "$SYS/ufw-configured" ] && echo yes || echo no; }

# A new machine: the firewall is set up, and recorded machine-wide.
setup no no
run
assert_eq "new machine: exits 0" "0" "$STATUS"
assert_contains "new machine: firewall turned on" "$CALLS" "sudo ufw enable"
assert_contains "new machine: inbound denied" "$CALLS" "sudo ufw default deny incoming"
assert_eq "new machine: recorded machine-wide" "yes" "$(machine_marked)"
mock_cleanup

# An existing install (this user's old marker): recorded, nothing changed.
setup yes no
run
assert_eq "existing install: exits 0" "0" "$STATUS"
assert_not_contains "existing install: firewall not touched" "$CALLS" "sudo ufw"
assert_eq "existing install: recorded machine-wide" "yes" "$(machine_marked)"
mock_cleanup

# A second user on a machine that's already set up: nothing at all, so a
# firewall someone turned off stays off.
setup no yes
run
assert_eq "second user: exits 0" "0" "$STATUS"
assert_eq "second user: nothing run" "" "$CALLS"
mock_cleanup

test_summary
