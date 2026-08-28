#!/bin/bash
#
# Unit tests for install.sh's DISTRO_OK detection - specifically the
# linuxmint case, which has to recognize two different lineages under the
# same ID=linuxmint: LMDE (Debian-based, DEBIAN_CODENAME=trixie) and regular
# Mint (Ubuntu-based, UBUNTU_CODENAME=noble, no DEBIAN_CODENAME at all). A
# real bug was found here - the check only looked for DEBIAN_CODENAME, so
# every regular-Mint install hit the "untested and unsupported" warning even
# though regular Mint is the actual target platform. These tests pin the fix
# down and guard against regressing either lineage.
#
# Deliberately NOT using --yes here: --yes skips the distro-warning prompt
# outright regardless of DISTRO_OK's value, which would make these tests
# pass identically whether or not the linuxmint case was actually correct -
# exactly the blind spot that let the original bug through unnoticed. Instead
# each scenario runs interactively with enough blank-line stdin to satisfy
# every prompt this path can reach (at most two: the distro warning, then the
# welcome message), and asserts on whether the distro-warning text itself
# showed up - that's what actually depends on DISTRO_OK.
#
# SAFETY: every scenario below keeps OHMYDEBN_TEST_SKIP_CONFIG=1 set - see
# test-install-assume-yes.sh for why.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install.sh: distro detection ==="

setup_mocks() {
  mock_bin dpkg <<'EOF'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn" ]] && exit 0
exit 1
EOF
  mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF
  mock_bin curl <<'EOF'
#!/bin/bash
mock_log "curl $*"
exit 0
EOF
  mock_bin clear <<'EOF'
#!/bin/bash
exit 0
EOF
}

WARNING_TEXT="untested and unsupported"

# run_scenario <description> <expect distro-ok: yes|no> <os-release lines...>
run_scenario() {
  local desc="$1" expect_ok="$2"
  shift 2
  mock_init
  setup_mocks
  printf '%s\n' "$@" >"$MOCK_DIR/os-release"
  SCRATCH_HOME=$(mktemp -d)
  # Two blank lines cover the two `read -r _` prompts this path can reach
  # (distro warning, welcome message) - any prompts that don't fire just
  # leave stdin partially unread, which is harmless.
  OUTPUT=$(HOME="$SCRATCH_HOME" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" \
    OHMYDEBN_TEST_SKIP_CONFIG=1 PATH="$(mock_path)" \
    bash "$SCRIPT" < <(printf '\n\n') 2>&1)
  EXIT_CODE=$?
  assert_eq "$desc: exits cleanly" "0" "$EXIT_CODE"
  assert_contains "$desc: reaches the config-layer skip" "$OUTPUT" \
    "OHMYDEBN_TEST_SKIP_CONFIG set - skipping desktop-config layer"
  if [[ "$expect_ok" == "yes" ]]; then
    assert_not_contains "$desc: distro warning NOT shown" "$OUTPUT" "$WARNING_TEXT"
  else
    assert_contains "$desc: distro warning shown" "$OUTPUT" "$WARNING_TEXT"
  fi
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

run_scenario "LMDE (DEBIAN_CODENAME=trixie)" "yes" \
  "ID=linuxmint" "DEBIAN_CODENAME=trixie"

run_scenario "regular Mint 22.3 Zena (UBUNTU_CODENAME=noble, no DEBIAN_CODENAME)" "yes" \
  "ID=linuxmint" "VERSION_CODENAME=zena" "UBUNTU_CODENAME=noble"

run_scenario "linuxmint with neither codename set" "no" \
  "ID=linuxmint"

run_scenario "Debian trixie" "yes" \
  "ID=debian" "VERSION_CODENAME=trixie"

run_scenario "Kali rolling" "yes" \
  "ID=kali" "VERSION_CODENAME=kali-rolling"

run_scenario "unrelated distro" "no" \
  "ID=fedora" "VERSION_CODENAME=41"

test_summary
