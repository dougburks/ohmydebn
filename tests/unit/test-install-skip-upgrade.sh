#!/bin/bash
#
# Unit tests for install.sh --skip-upgrade: the flag must reach the
# finalization stage that honors it (install/finalization/updates.sh, sourced
# from ohmydebn.sh, a separate file - so it travels as the exported
# OHMYDEBN_SKIP_UPGRADE), install.sh must record OHMYDEBN_RUN_START for the
# headline timestamps, and updates.sh must skip only the full upgrade -
# the rest of that stage still runs. Not the default: without the flag
# the upgrade runs as always.
#
# SAFETY: same mocks as test-install-distro-detection.sh (dpkg says
# ohmydebn is installed, sudo/curl/clear are stubs), and install.sh's
# `source /usr/share/ohmydebn/ohmydebn.sh` line is patched to dump the
# environment instead - nothing real is sourced or installed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install.sh --skip-upgrade / finalization/updates.sh ==="

# --- install.sh: the flag is exported for the config layer, run start recorded ---
setup_install() {
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn" ]] && exit 0
exit 1
EOF2
  for stub in sudo curl clear; do mock_bin "$stub" <<'EOF2'
#!/bin/bash
exit 0
EOF2
  done
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/state"; : >"$SCRATCH_HOME/.local/state/ohmydebn"  # not a first install
  printf 'ID=debian\nVERSION_CODENAME=trixie\n' >"$MOCK_DIR/os-release"
  sed "s#^source /usr/share/ohmydebn/ohmydebn.sh.*#env >\"$MOCK_DIR/env-at-config-layer\"#" "$REPO_ROOT/install.sh" >"$MOCK_DIR/install-patched.sh"
}

run_install() {
  HOME="$SCRATCH_HOME" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" PATH="$(mock_path)" \
    bash "$MOCK_DIR/install-patched.sh" "$@" </dev/null >/dev/null 2>&1
}

setup_install
run_install --yes --skip-upgrade
ENV_SEEN=$(cat "$MOCK_DIR/env-at-config-layer" 2>/dev/null)
assert_contains "--skip-upgrade: OHMYDEBN_SKIP_UPGRADE=1 reaches the config layer" "$ENV_SEEN" "OHMYDEBN_SKIP_UPGRADE=1"
assert_eq "--skip-upgrade: OHMYDEBN_RUN_START is a recent epoch second" "yes" \
  "$(v=$(sed -n 's/^OHMYDEBN_RUN_START=//p' "$MOCK_DIR/env-at-config-layer"); [[ "$v" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS - v < 60 )) && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"; mock_cleanup

setup_install
run_install --yes
ENV_SEEN=$(cat "$MOCK_DIR/env-at-config-layer" 2>/dev/null)
assert_not_contains "no flag: OHMYDEBN_SKIP_UPGRADE is not set (the upgrade stays the default)" "$ENV_SEEN" "OHMYDEBN_SKIP_UPGRADE"
assert_contains "no flag: run start still recorded" "$ENV_SEEN" "OHMYDEBN_RUN_START="
rm -rf "$SCRATCH_HOME"; mock_cleanup

setup_install
START_BEFORE=$((EPOCHSECONDS - 500))
HOME="$SCRATCH_HOME" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" PATH="$(mock_path)" OHMYDEBN_RUN_START="$START_BEFORE" \
  bash "$MOCK_DIR/install-patched.sh" --yes </dev/null >/dev/null 2>&1
assert_contains "run start: an inherited value (from ohmydebn-update) is kept, not overwritten" \
  "$(cat "$MOCK_DIR/env-at-config-layer")" "OHMYDEBN_RUN_START=$START_BEFORE"
rm -rf "$SCRATCH_HOME"; mock_cleanup

# --- finalization/updates.sh honors the flag, and only for the upgrade ---
setup_updates() {
  mock_init
  for stub in ohmydebn-headline ohmydebn-update-system-pkgs ohmydebn-opencode-migrate ohmydebn-update-check-install; do
    mock_bin "$stub" <<EOF2
#!/bin/bash
mock_log "$stub \$*"
EOF2
  done
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/install/finalization/updates.sh" >"$MOCK_DIR/updates-patched.sh"
}

setup_updates
OUTPUT=$(PATH="$(mock_path)" OHMYDEBN_SKIP_UPGRADE=1 bash -e "$MOCK_DIR/updates-patched.sh" 2>&1)
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "updates.sh (skip): the full upgrade is NOT run" "$CALLS" "ohmydebn-update-system-pkgs"
assert_contains "updates.sh (skip): says so in a headline" "$CALLS" "ohmydebn-headline Skipping the full system update (--skip-upgrade)"
assert_contains "updates.sh (skip): tells the user how to catch up" "$OUTPUT" "Run ohmydebn-update when convenient"
assert_contains "updates.sh (skip): the rest of the stage still runs (opencode migrate)" "$CALLS" "ohmydebn-opencode-migrate"
assert_contains "updates.sh (skip): the rest of the stage still runs (update-check timer)" "$CALLS" "ohmydebn-update-check-install"
mock_cleanup

setup_updates
PATH="$(mock_path)" bash -e "$MOCK_DIR/updates-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "updates.sh (default): the full upgrade runs" "$CALLS" "ohmydebn-update-system-pkgs"
assert_contains "updates.sh (default): with its usual headline" "$CALLS" "ohmydebn-headline Installing any available package updates"
mock_cleanup

setup_updates
PATH="$(mock_path)" OHMYDEBN_SKIP_UPGRADE=0 bash -e "$MOCK_DIR/updates-patched.sh" >/dev/null 2>&1
assert_contains "updates.sh (flag set to 0): the upgrade runs - only exactly 1 skips" "$(cat "$MOCK_CALLS")" "ohmydebn-update-system-pkgs"
mock_cleanup

test_summary
