#!/bin/bash
#
# Unit tests for bin/ohmydebn-virtmanager-install. Covers two behavior
# changes from the original script (which just ran a flat `apt install
# qemu-kvm virt-manager ...`):
#
#  1. qemu-kvm is a virtual package with no installation candidate on
#     Debian trixie - the script now maps the host's `dpkg
#     --print-architecture` to a concrete qemu-system-* package instead.
#
#  2. The install now sets up qemu:///session (unprivileged, per-user)
#     rather than qemu:///system: no libvirt group / libvirtd enable, but a
#     session-mode storage pool has to be defined by hand (system mode gets
#     one for free from the package, session mode doesn't) - and only when
#     one doesn't already exist, so re-running the installer is idempotent.
#     virt-manager's own gsettings also get pointed at the session URI so
#     it doesn't open onto an empty connection list.
#
# This only covers the fresh-install path; there is deliberately no
# migration logic for existing qemu:///system installs (out of scope by
# design - see the conversation this change came from).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-virtmanager-install"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-virtmanager-install ==="

# dpkg mock: virt-manager always reports "not installed" (so the install
# block runs), --print-architecture answers with whatever arch is under
# test.
mock_dpkg_not_installed() {
  local arch="$1"
  mock_bin dpkg <<EOF
#!/bin/bash
[[ "\$1" == "-s" ]] && exit 1
[[ "\$1" == "--print-architecture" ]] && echo "$arch" && exit 0
exit 1
EOF
}

setup_common_mocks() {
  mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF
  mock_bin cinnamon <<'EOF'
#!/bin/bash
mock_log "cinnamon $*"
exit 0
EOF
  mock_bin gsettings <<'EOF'
#!/bin/bash
mock_log "gsettings $*"
exit 0
EOF
}

# virsh mock: pool-info's exit code controls whether the "default" session
# pool is reported as already existing.
mock_virsh() {
  local pool_info_exit="$1"
  mock_bin virsh <<EOF
#!/bin/bash
mock_log "virsh \$*"
[[ "\$3" == "pool-info" ]] && exit $pool_info_exit
exit 0
EOF
}

# The script invokes /usr/bin/cinnamon by absolute path, which skips PATH
# entirely - a bare `mock_bin cinnamon` never intercepts it, and running the
# real script would restart the actual live Cinnamon session (found the hard
# way: it did, repeatedly, mid test-run). Patch the absolute path to the
# mock dir first, same technique test-spice-vdagent.sh uses for this exact
# class of problem.
patched_script() {
  sed "s#/usr/bin/cinnamon#$MOCK_BIN/cinnamon#g" "$SCRIPT" >"$MOCK_DIR/virtmanager-install-patched.sh"
  echo "$MOCK_DIR/virtmanager-install-patched.sh"
}

# Scenario 1: amd64 host, no pre-existing pool -> qemu-system-x86 gets
# installed (never qemu-kvm), only the kvm group is added (never libvirt or
# a libvirtd enable), the session pool gets defined+autostarted+started,
# and virt-manager's default connection is pointed at qemu:///session.
mock_init
mock_dpkg_not_installed amd64
setup_common_mocks
mock_virsh 1
USER=testuser PATH="$(mock_path)" bash "$(patched_script)" <<<"" >/dev/null 2>&1
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "amd64: exits cleanly" "0" "$EXIT_CODE"
assert_contains "amd64: installs qemu-system-x86" "$CALLS" "install qemu-system-x86 virt-manager"
assert_not_contains "amd64: never installs qemu-kvm" "$CALLS" "qemu-kvm"
assert_contains "amd64: adds the kvm group" "$CALLS" "adduser testuser kvm"
assert_not_contains "amd64: never adds the libvirt group" "$CALLS" "adduser testuser libvirt"
assert_not_contains "amd64: never enables/starts system libvirtd" "$CALLS" "libvirtd"
assert_contains "amd64: defines the session pool (missing)" "$CALLS" "pool-define-as default dir --target"
assert_contains "amd64: autostarts the session pool" "$CALLS" "pool-autostart default"
assert_contains "amd64: starts the session pool" "$CALLS" "pool-start default"
assert_contains "amd64: points virt-manager at qemu:///session (uris)" "$CALLS" "uris ['qemu:///session']"
assert_contains "amd64: points virt-manager at qemu:///session (autoconnect)" "$CALLS" "autoconnect ['qemu:///session']"
mock_cleanup

# Scenario 2: arm64 host -> the architecture case statement picks
# qemu-system-arm instead of the amd64 default.
mock_init
mock_dpkg_not_installed arm64
setup_common_mocks
mock_virsh 1
USER=testuser PATH="$(mock_path)" bash "$(patched_script)" <<<"" >/dev/null 2>&1
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "arm64: exits cleanly" "0" "$EXIT_CODE"
assert_contains "arm64: installs qemu-system-arm" "$CALLS" "install qemu-system-arm virt-manager"
mock_cleanup

# Scenario 3: unrecognized architecture -> falls back to qemu-system-x86
# rather than failing outright.
mock_init
mock_dpkg_not_installed sparc64
setup_common_mocks
mock_virsh 1
USER=testuser PATH="$(mock_path)" bash "$(patched_script)" <<<"" >/dev/null 2>&1
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "unknown arch: exits cleanly" "0" "$EXIT_CODE"
assert_contains "unknown arch: falls back to qemu-system-x86" "$CALLS" "install qemu-system-x86 virt-manager"
mock_cleanup

# Scenario 4: session pool already exists -> re-running the installer must
# not try to redefine/restart it (idempotency), even though the rest of the
# install (packages, groups, gsettings) still runs.
mock_init
mock_dpkg_not_installed amd64
setup_common_mocks
mock_virsh 0
USER=testuser PATH="$(mock_path)" bash "$(patched_script)" <<<"" >/dev/null 2>&1
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "pool exists: exits cleanly" "0" "$EXIT_CODE"
assert_contains "pool exists: still checks pool-info" "$CALLS" "pool-info default"
assert_not_contains "pool exists: never redefines the pool" "$CALLS" "pool-define-as"
assert_not_contains "pool exists: never re-autostarts the pool" "$CALLS" "pool-autostart"
assert_not_contains "pool exists: never re-starts the pool" "$CALLS" "pool-start"
assert_contains "pool exists: kvm group still added" "$CALLS" "adduser testuser kvm"
mock_cleanup

# Scenario 5: virt-manager already installed -> the whole install block is
# skipped, nothing gets called at all.
mock_init
mock_bin dpkg <<'EOF'
#!/bin/bash
[[ "$1" == "-s" ]] && exit 0
exit 1
EOF
setup_common_mocks
mock_virsh 0
USER=testuser PATH="$(mock_path)" bash "$(patched_script)" <<<"" >/dev/null 2>&1
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "already installed: exits cleanly" "0" "$EXIT_CODE"
assert_eq "already installed: nothing called at all" "" "$CALLS"
mock_cleanup

test_summary
