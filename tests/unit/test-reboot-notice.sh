#!/bin/bash
#
# Unit tests for install/finalization/reboot-notice.sh - the end-of-update
# "a reboot is needed" notice. Its three inputs (running kernel, /boot,
# the /run/reboot-required marker) are sed-patched to scratch values and
# ohmydebn-headline/notify-send are mocked, so this runs the same on any
# box regardless of its real kernel state.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/finalization/reboot-notice.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/finalization/reboot-notice.sh ==="

# setup <running kernel> <installed kernel versions...>
setup() {
  local running="$1"; shift
  mock_init
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF2
  mock_bin notify-send <<'EOF2'
#!/bin/bash
mock_log "notify-send $*"
EOF2
  BOOT="$MOCK_DIR/boot"; mkdir -p "$BOOT"
  for v in "$@"; do : >"$BOOT/vmlinuz-$v"; done
  MARKER="$MOCK_DIR/run/reboot-required"; mkdir -p "$(dirname "$MARKER")"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#^RUNNING_KERNEL=.*#RUNNING_KERNEL='$running'#; s#^BOOT_DIR=.*#BOOT_DIR='$BOOT'#; s#^REBOOT_REQUIRED_FILE=.*#REBOOT_REQUIRED_FILE='$MARKER'#" \
    "$SCRIPT" >"$MOCK_DIR/patched.sh"
}

run_notice() {
  OUTPUT=$(DISPLAY=:0 PATH="$(mock_path)" bash -e "$MOCK_DIR/patched.sh" 2>&1)
  EXIT_CODE=$?
}

# --- running the newest kernel, no marker: silent ---
setup "6.12.107+deb13-amd64" "6.12.105+deb13-amd64" "6.12.107+deb13-amd64"
run_notice
assert_eq "up to date: exits 0" "0" "$EXIT_CODE"
assert_eq "up to date: prints nothing" "" "$OUTPUT"
assert_eq "up to date: no headline, no notification" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- a newer kernel was installed than the one running ---
setup "6.12.105+deb13-amd64" "6.12.105+deb13-amd64" "6.12.107+deb13-amd64"
run_notice
assert_eq "newer kernel: exits 0" "0" "$EXIT_CODE"
assert_contains "newer kernel: headline shown" "$(cat "$MOCK_CALLS")" "ohmydebn-headline A reboot is needed to finish this update"
assert_contains "newer kernel: names both versions" "$OUTPUT" "A newer kernel (6.12.107+deb13-amd64) is installed, but 6.12.105+deb13-amd64 is still running."
assert_contains "newer kernel: says nothing is broken meanwhile" "$OUTPUT" "Reboot when it's convenient"
assert_contains "newer kernel: desktop notification sent under a display" "$(cat "$MOCK_CALLS")" "notify-send OhMyDebn Update A reboot is needed"
mock_cleanup

# --- version sort, not string sort: 6.12.10 running beats an installed 6.12.9 ---
setup "6.12.10-amd64" "6.12.9-amd64" "6.12.10-amd64"
run_notice
assert_eq "version ordering: 6.12.10 running vs 6.12.9 installed is silent" "" "$OUTPUT"
mock_cleanup

# --- running a kernel NEWER than any installed image (a just-removed old image, or a custom kernel): silent ---
setup "6.13.0-custom" "6.12.107+deb13-amd64"
run_notice
assert_eq "running kernel newer than installed images: silent" "" "$OUTPUT"
mock_cleanup

# --- no vmlinuz images at all (Raspberry Pi OS keeps kernels elsewhere): silent ---
setup "6.12.25+rpt-rpi-v8"
run_notice
assert_eq "no /boot/vmlinuz-*: silent" "" "$OUTPUT"
mock_cleanup

# --- the reboot-required marker, with and without a package list ---
setup "6.12.107+deb13-amd64" "6.12.107+deb13-amd64"
: >"$MARKER"
printf 'linux-image-6.12.107\nlibc6\nlinux-image-6.12.107\n' >"$MARKER.pkgs"
run_notice
assert_contains "marker+pkgs: headline shown" "$(cat "$MOCK_CALLS")" "ohmydebn-headline A reboot is needed"
assert_contains "marker+pkgs: lists the packages, de-duplicated" "$OUTPUT" "These packages asked for a reboot: libc6 linux-image-6.12.107 "
assert_not_contains "marker+pkgs: no kernel line when the kernel is current" "$OUTPUT" "A newer kernel"
mock_cleanup

setup "6.12.107+deb13-amd64" "6.12.107+deb13-amd64"
: >"$MARKER"
run_notice
assert_contains "marker only: generic reason" "$OUTPUT" "The system has flagged that a reboot is required."
mock_cleanup

# --- both signals at once: both reasons, one headline ---
setup "6.12.105+deb13-amd64" "6.12.107+deb13-amd64"
: >"$MARKER"
run_notice
assert_contains "both: kernel reason present" "$OUTPUT" "A newer kernel"
assert_contains "both: marker reason present" "$OUTPUT" "flagged that a reboot is required"
assert_eq "both: exactly one headline" "1" "$(grep -c ohmydebn-headline "$MOCK_CALLS")"
mock_cleanup

# --- no display: notice printed, but no notify-send attempted ---
setup "6.12.105+deb13-amd64" "6.12.107+deb13-amd64"
OUTPUT=$(env -u DISPLAY PATH="$(mock_path)" bash -e "$MOCK_DIR/patched.sh" 2>&1)
assert_contains "no display: still printed" "$OUTPUT" "A newer kernel"
assert_not_contains "no display: no notification" "$(cat "$MOCK_CALLS")" "notify-send"
mock_cleanup

test_summary
