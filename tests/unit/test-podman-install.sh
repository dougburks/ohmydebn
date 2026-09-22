#!/bin/bash
#
# Unit tests for bin/ohmydebn-podman-installed and bin/ohmydebn-podman-
# install. uidmap and passt are only Recommends of podman; on a distro
# that skips recommends (LCOS) the podman package alone can't map IDs or
# publish ports, so SO-CRATES failed with a pasta error until passt was
# installed by hand. These verify the "installed?" gate treats podman
# without those extras as incomplete, and that the installer installs
# exactly what's missing - repairing a bare podman as well as installing
# from scratch - then always runs the subordinate-ID backfill.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLED="$REPO_ROOT/bin/ohmydebn-podman-installed"
INSTALL="$REPO_ROOT/bin/ohmydebn-podman-install"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-podman-installed + bin/ohmydebn-podman-install ==="

# setup_mocks <installed-pkg>...: the dpkg stub reports exactly these
# packages as installed.
setup_mocks() {
  FAKE_INSTALLED=" $* "
  export FAKE_INSTALLED
  mock_bin dpkg <<'EOF'
#!/bin/bash
# only `dpkg -s <pkg>` is ever used here
[[ "$FAKE_INSTALLED" == *" $2 "* ]]
EOF
  mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "sudo $*"
EOF
  mock_bin ohmydebn-podman-subids-ensure <<'EOF'
#!/bin/bash
mock_log "ohmydebn-podman-subids-ensure $*"
EOF
  cp "$INSTALLED" "$MOCK_BIN/ohmydebn-podman-installed"
  sed -e "s#/usr/share/ohmydebn/bin/#$MOCK_BIN/#g" "$INSTALL" >"$MOCK_DIR/install-patched.sh"
}

run_installed() {
  PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-podman-installed" "$@" 2>&1
}

run_install() {
  # A newline on stdin satisfies the "Press Enter" read on the prompting path.
  printf '\n' | PATH="$(mock_path)" bash "$MOCK_DIR/install-patched.sh" "$@" 2>&1
}

# -- ohmydebn-podman-installed --

mock_init
setup_mocks podman uidmap passt
run_installed >/dev/null
assert_eq "installed: all three present -> exit 0" "0" "$?"
assert_eq "installed: --missing prints nothing when complete" "" "$(run_installed --missing)"
mock_cleanup

mock_init
setup_mocks podman
run_installed >/dev/null
assert_eq "installed: podman without extras -> non-zero" "1" "$?"
assert_eq "installed: --missing lists the extras" "uidmap
passt" "$(run_installed --missing)"
mock_cleanup

mock_init
setup_mocks
assert_eq "installed: nothing present -> --missing lists all three" "podman
uidmap
passt" "$(run_installed --missing)"
mock_cleanup

# -- ohmydebn-podman-install --

# Scenario 1: everything present -> no apt, says so, still runs the
# subordinate-ID backfill.
mock_init
setup_mocks podman uidmap passt
OUT=$(run_install --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "complete: reports already installed" "$OUT" "Podman is already installed."
assert_not_contains "complete: apt not invoked" "$CALLS" "apt"
assert_contains "complete: subids-ensure still runs" "$CALLS" "ohmydebn-podman-subids-ensure"
mock_cleanup

# Scenario 2: nothing installed -> apt update + install all three, then
# the backfill.
mock_init
setup_mocks
run_install --skip-prompt >/dev/null
CALLS=$(cat "$MOCK_CALLS")
assert_contains "fresh: apt update runs" "$CALLS" "sudo /usr/bin/apt update"
assert_contains "fresh: installs podman uidmap passt" "$CALLS" "sudo /usr/bin/apt -y install podman uidmap passt"
assert_contains "fresh: subids-ensure runs" "$CALLS" "ohmydebn-podman-subids-ensure"
mock_cleanup

# Scenario 3: bare podman already present (the LCOS case) -> installs
# only the missing extras, and the prompt explains why rather than
# claiming podman isn't installed.
mock_init
setup_mocks podman
OUT=$(run_install)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "bare podman: installs just the extras" "$CALLS" "sudo /usr/bin/apt -y install uidmap passt"
assert_not_contains "bare podman: doesn't reinstall podman" "$CALLS" "install podman"
assert_contains "bare podman: prompt names the missing packages" "$OUT" "missing packages rootless mode needs: uidmap passt"
assert_not_contains "bare podman: prompt doesn't say podman is absent" "$OUT" "Podman is not currently installed."
mock_cleanup

# Scenario 4: --skip-prompt suppresses the Enter prompt entirely.
mock_init
setup_mocks
OUT=$(run_install --skip-prompt)
assert_not_contains "--skip-prompt: no Enter prompt" "$OUT" "Press Enter"
mock_cleanup

test_summary
