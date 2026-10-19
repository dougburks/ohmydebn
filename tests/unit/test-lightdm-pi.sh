#!/bin/bash
#
# Unit tests for install/finalization/lightdm.sh - pointing Raspberry Pi
# OS's lightdm.conf at Cinnamon instead of its rpd-labwc session. The
# original is backed up once, to lightdm.conf.BEFORE.OHMYDEBN, and never
# replaced by a later edit's already-edited copy (default-session.sh
# shares the backup).
#
# sudo is mocked to log and then run its command, ohmydebn-headline is
# mocked, and lightdm.conf is patched to a scratch file.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/finalization/lightdm.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/finalization/lightdm.sh ==="

setup() {
  mock_init
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
exec "$@"
EOF2
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF2
  CONF="$MOCK_DIR/lightdm.conf"
  BACKUP="$CONF.BEFORE.OHMYDEBN"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#^LIGHTDM_CONF=/etc/lightdm/lightdm.conf#LIGHTDM_CONF=$CONF#" "$SCRIPT" >"$MOCK_DIR/patched.sh"
}
run_script() { PATH="$(mock_path)" bash -e "$MOCK_DIR/patched.sh" </dev/null >"$MOCK_DIR/output" 2>&1; echo $?; }

PI_CONF="[Seat:*]
greeter-session=pi-greeter-labwc
user-session=rpd-labwc
autologin-session=rpd-labwc"

# --- Raspberry Pi OS, first run: switched to Cinnamon, original backed up ---
setup
printf '%s\n' "$PI_CONF" >"$CONF"
assert_eq "first run: exits 0" "0" "$(run_script)"
assert_eq "first run: every rpd-labwc session is now cinnamon" "user-session=cinnamon
autologin-session=cinnamon" "$(grep -E '^(user|autologin)-session=' "$CONF")"
assert_eq "first run: the original is backed up" "$PI_CONF" "$(cat "$BACKUP")"
assert_contains "first run: headline" "$(cat "$MOCK_CALLS")" "ohmydebn-headline Updating $CONF to log into cinnamon desktop"
mock_cleanup

# --- rpd-labwc back again later: switched again, the first backup kept ---
setup
printf '%s\n' "$PI_CONF" >"$CONF"
echo "the original" >"$BACKUP"
assert_eq "again: exits 0" "0" "$(run_script)"
assert_eq "again: switched to cinnamon" "user-session=cinnamon" "$(grep '^user-session=' "$CONF")"
assert_eq "again: the original backup is kept" "the original" "$(cat "$BACKUP")"
mock_cleanup

# --- not Raspberry Pi OS (or already switched): nothing touched ---
setup
printf '[Seat:*]\nuser-session=cinnamon\n' >"$CONF"
assert_eq "no rpd-labwc: exits 0" "0" "$(run_script)"
assert_eq "no rpd-labwc: nothing run" "" "$(cat "$MOCK_CALLS")"
assert_eq "no rpd-labwc: no backup made" "no" "$([ -e "$BACKUP" ] && echo yes || echo no)"
mock_cleanup

# --- no lightdm.conf at all: nothing touched ---
setup
assert_eq "no lightdm.conf: exits 0" "0" "$(run_script)"
assert_eq "no lightdm.conf: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

test_summary
