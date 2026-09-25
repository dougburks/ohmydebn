#!/bin/bash
#
# Unit tests for bin/ohmydebn-update-firmware (OhMyDebn Menu > Update >
# Firmware): installs fwupd when it's missing, stops if the LVFS metadata
# can't be refreshed, and reads fwupdmgr update's exit status - 0 updated,
# 2 nothing to do (every VM, and devices LVFS doesn't cover), anything else
# a failure. On UEFI machines it also installs fwupd-signed when the signed
# EFI updater is missing (MX Linux skips apt recommends). fwupdmgr, sudo,
# apt, /sys/firmware/efi and the signed-updater path are all mocked, so
# nothing here touches real firmware.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-update-firmware ==="

# setup <fwupd installed: yes|no> <refresh exit> <update exit>
#       [uefi: yes|no (default no)] [signed updater present: yes|no (default no)]
#       [fwupd-signed install exit (default 0)]
setup() {
  local installed="$1" refresh_exit="$2" update_exit="$3"
  local uefi="${4:-no}" signed="${5:-no}" signed_exit="${6:-0}"
  mock_init
  mkdir -p "$MOCK_DIR/efi-libexec"
  [[ "$uefi" == "yes" ]] && mkdir -p "$MOCK_DIR/sys-efi"
  [[ "$signed" == "yes" ]] && touch "$MOCK_DIR/efi-libexec/fwupdx64.efi.signed"
  echo "$signed_exit" >"$MOCK_DIR/signed-exit"
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$1" == "fwupdmgr" ]] && exec "$@"
[[ "$*" == *"install fwupd-signed"* ]] && exit "$(cat "$MOCK_DIR/signed-exit")"
exit 0
EOF2
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
echo "== $*"
EOF2
  if [[ "$installed" == "yes" ]]; then
    mock_bin fwupdmgr <<EOF2
#!/bin/bash
mock_log "fwupdmgr \$*"
case "\$1" in
refresh) exit $refresh_exit ;;
update) exit $update_exit ;;
esac
EOF2
  fi
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#^EFI_SYSFS=.*#EFI_SYSFS=$MOCK_DIR/sys-efi#; s#^SIGNED_EFI_GLOB=.*#SIGNED_EFI_GLOB=\"$MOCK_DIR/efi-libexec/fwupd*.efi.signed\"#" \
    "$REPO_ROOT/bin/ohmydebn-update-firmware" >"$MOCK_BIN/ohmydebn-update-firmware"
  chmod +x "$MOCK_BIN/ohmydebn-update-firmware"
}

run() {
  # A PATH without the real /usr/bin/fwupdmgr, so "not installed" is real.
  OUT=$(PATH="$MOCK_BIN:/usr/bin:/bin" bash -c '
    hide=$(mktemp -d)
    for cmd in bash sed grep cat mktemp rm env; do ln -s "$(command -v "$cmd")" "$hide/$cmd"; done
    PATH="$MOCK_BIN:$hide" bash "$MOCK_BIN/ohmydebn-update-firmware"
    status=$?
    rm -rf "$hide"
    exit $status' </dev/null 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

# --- updates applied ---
setup yes 0 0
run
assert_eq "updated: exits 0" "0" "$STATUS"
assert_contains "updated: refreshes LVFS metadata first" "$CALLS" "sudo fwupdmgr refresh --force"
assert_contains "updated: runs the update" "$CALLS" "sudo fwupdmgr update"
assert_contains "updated: says it finished" "$OUT" "Firmware update finished."
assert_not_contains "updated: fwupd already there, no apt" "$CALLS" "apt"
assert_contains "updated: warns to stay plugged in" "$OUT" "Keep your computer plugged in"
mock_cleanup

# --- nothing to do (exit 2) is success ---
setup yes 0 2
run
assert_eq "nothing to do: exits 0" "0" "$STATUS"
assert_contains "nothing to do: says firmware is up to date" "$OUT" "Your firmware is up to date."
assert_not_contains "nothing to do: not reported as a failure" "$OUT" "didn't complete"
mock_cleanup

# --- update failure ---
setup yes 0 1
run
assert_eq "update failed: exits 1" "1" "$STATUS"
assert_contains "update failed: says so" "$OUT" "The firmware update didn't complete."
mock_cleanup

# --- metadata refresh failure stops before updating ---
setup yes 1 0
run
assert_eq "refresh failed: exits 1" "1" "$STATUS"
assert_contains "refresh failed: points at the connection" "$OUT" "Could not download firmware information from LVFS."
assert_not_contains "refresh failed: no update attempted" "$CALLS" "fwupdmgr update"
mock_cleanup

# --- fwupd missing: installed first ---
setup no 0 0
run
assert_contains "not installed: refreshes apt" "$CALLS" "sudo /usr/bin/apt update"
assert_contains "not installed: installs fwupd" "$CALLS" "sudo /usr/bin/apt -y install fwupd"
mock_cleanup

# --- legacy BIOS: never installs the signed UEFI updater ---
setup yes 0 2 no no
run
assert_not_contains "BIOS: no fwupd-signed" "$CALLS" "fwupd-signed"
mock_cleanup

# --- UEFI, signed updater already there (Debian installs recommends) ---
setup yes 0 2 yes yes
run
assert_not_contains "UEFI + signed present: nothing extra installed" "$CALLS" "apt"
mock_cleanup

# --- UEFI, signed updater missing (MX Linux): installed before updating ---
setup yes 0 0 yes no
run
assert_contains "UEFI + signed missing: refreshes apt" "$CALLS" "sudo /usr/bin/apt update"
assert_contains "UEFI + signed missing: installs fwupd-signed" "$CALLS" "sudo /usr/bin/apt -y install fwupd-signed"
assert_eq "UEFI + signed missing: then updates as usual" "0" "$STATUS"
mock_cleanup

# --- fresh install on UEFI: one apt update covers both installs ---
setup no 0 0 yes no
run
assert_eq "fresh UEFI install: apt update runs once" "1" "$(grep -c 'sudo /usr/bin/apt update' <<<"$CALLS")"
assert_contains "fresh UEFI install: installs fwupd-signed too" "$CALLS" "sudo /usr/bin/apt -y install fwupd-signed"
mock_cleanup

# --- fwupd-signed can't be installed: warn, but still update other firmware ---
setup yes 0 0 yes no 100
run
assert_contains "signed install fails: explains the effect" "$OUT" "UEFI (BIOS) updates may not install at restart while Secure Boot is on."
assert_contains "signed install fails: still runs the update" "$CALLS" "sudo fwupdmgr update"
assert_eq "signed install fails: exits 0 when the update itself succeeds" "0" "$STATUS"
mock_cleanup

test_summary
