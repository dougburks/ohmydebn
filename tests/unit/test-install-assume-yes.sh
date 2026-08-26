#!/bin/bash
#
# Unit tests for install.sh's --yes flag and the OS-release override it
# reuses from bin/ohmydebn-pkg-remove-all-optional (OHMYDEBN_TEST_OS_RELEASE).
#
# --yes exists so install.sh can run unattended (the install-drift-monitor.yml
# CI workflow, or scripted provisioning): it must skip every "Press Enter to
# continue" prompt without blocking on stdin. A real bug was found the hard
# way here - the welcome-message block's `clear` call wasn't gated by --yes,
# and `clear` fails outright with no TERM/TTY (any headless container), which
# killed the whole script under `set -e`. These tests pin that fix down.
#
# SAFETY: every scenario below keeps OHMYDEBN_TEST_SKIP_CONFIG=1 set. Without
# it, install.sh sources /usr/share/ohmydebn/ohmydebn.sh by its real absolute
# path - not resolvable through PATH mocking - which on a real OhMyDebn
# machine (this dev box included) would actually apply the desktop-config
# layer (gsettings, systemctl, theming) for real. Do not add a scenario that
# leaves it unset.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install.sh: --yes ==="

setup_mocks() {
  # Already installed, so the script never reaches a real `apt install
  # ohmydebn` - keeps every scenario fast and independent of network access.
  mock_bin dpkg <<'EOF'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn" ]] && exit 0
exit 1
EOF
  # Every root-requiring command in install.sh goes through sudo - mocking it
  # as a pure logger means nothing here ever touches the real system, no
  # matter which internal branch (apt sources detection, keyring, etc.) the
  # real host's existing /etc state happens to send the script through.
  mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF
  # Only reached if the real host is missing its ohmydebn keyring; mocked so
  # no scenario ever makes a real network call.
  mock_bin curl <<'EOF'
#!/bin/bash
mock_log "curl $*"
exit 0
EOF
  mock_bin clear <<'EOF'
#!/bin/bash
mock_log "clear"
exit 0
EOF
}

write_os_release() {
  cat >"$MOCK_DIR/os-release" <<EOF
ID=$1
VERSION_CODENAME=$2
EOF
}

# Scenario 1: unsupported distro + --yes -> the distro warning's prompt (and
# its clear) must not fire, and nothing here should block on stdin.
mock_init
setup_mocks
write_os_release arch ""
SCRATCH_HOME=$(mktemp -d)
OUTPUT=$(HOME="$SCRATCH_HOME" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" \
  OHMYDEBN_TEST_SKIP_CONFIG=1 PATH="$(mock_path)" \
  bash "$SCRIPT" --yes </dev/null 2>&1)
EXIT_CODE=$?
assert_eq "unsupported distro + --yes: exits cleanly, never blocks on stdin" "0" "$EXIT_CODE"
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "unsupported distro + --yes: clear never called" "$CALLS" "clear"
assert_contains "unsupported distro + --yes: welcome message still shown" "$OUTPUT" "Welcome to OhMyDebn!"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: supported distro, fresh install, + --yes -> the welcome
# message's own clear (unconditional before this fix) must also not fire,
# and the script must reach the config-layer skip cleanly.
mock_init
setup_mocks
write_os_release debian trixie
SCRATCH_HOME=$(mktemp -d)
OUTPUT=$(HOME="$SCRATCH_HOME" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" \
  OHMYDEBN_TEST_SKIP_CONFIG=1 PATH="$(mock_path)" \
  bash "$SCRIPT" --yes </dev/null 2>&1)
EXIT_CODE=$?
assert_eq "supported distro + --yes: exits cleanly" "0" "$EXIT_CODE"
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "supported distro + --yes: clear never called" "$CALLS" "clear"
assert_contains "supported distro + --yes: reaches the config-layer skip" "$OUTPUT" \
  "OHMYDEBN_TEST_SKIP_CONFIG set - skipping desktop-config layer"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: same, but WITHOUT --yes - the original interactive behavior
# (clear before the welcome message) must be unchanged. A single blank line
# on stdin satisfies the one `read` this path reaches (distro is supported
# and UID isn't 0, so neither of the other two prompts fire).
mock_init
setup_mocks
write_os_release debian trixie
SCRATCH_HOME=$(mktemp -d)
OUTPUT=$(HOME="$SCRATCH_HOME" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" \
  OHMYDEBN_TEST_SKIP_CONFIG=1 PATH="$(mock_path)" \
  bash "$SCRIPT" <<<"" 2>&1)
EXIT_CODE=$?
assert_eq "without --yes: still exits cleanly given input" "0" "$EXIT_CODE"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "without --yes: clear still called (unchanged default behavior)" "$CALLS" "clear"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
