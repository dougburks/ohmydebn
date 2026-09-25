#!/bin/bash
#
# Unit tests for ohmydebn.sh, the desktop-config layer install.sh hands off
# to (on a new install and on every ohmydebn-update). Its install/*/all.sh
# layers are replaced with stubs that record the environment they ran in.
#
# The guarded bug: a desktop session can point DCONF_PROFILE at its own
# dconf database. Pop!_OS's COSMIC exports DCONF_PROFILE=cosmic, so an
# install run from inside COSMIC wrote every Cinnamon setting to
# ~/.config/dconf/cosmic, which Cinnamon never reads - leaving the panel,
# applets and more at Cinnamon's defaults, with their one-time markers
# already set so nothing retried.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn.sh ==="

setup() {
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn" ]] && exit 0
exit 1
EOF2
  for layer in packaging config cleanup finalization; do
    mkdir -p "$MOCK_DIR/install/$layer"
    echo "mock_log \"$layer: DCONF_PROFILE=\${DCONF_PROFILE-<unset>}\"" >"$MOCK_DIR/install/$layer/all.sh"
  done
  sed "s#/usr/share/ohmydebn/install#$MOCK_DIR/install#g" "$REPO_ROOT/ohmydebn.sh" >"$MOCK_DIR/ohmydebn-patched.sh"
}

# --- run from COSMIC: every layer runs with DCONF_PROFILE cleared ---
setup
DCONF_PROFILE=cosmic PATH="$(mock_path)" bash "$MOCK_DIR/ohmydebn-patched.sh" </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
for layer in packaging config cleanup finalization; do
  assert_contains "from COSMIC: $layer runs with the default dconf profile" "$CALLS" "$layer: DCONF_PROFILE=<unset>"
done
assert_not_contains "from COSMIC: no layer sees DCONF_PROFILE=cosmic" "$CALLS" "DCONF_PROFILE=cosmic"
mock_cleanup

# --- run from Cinnamon (no DCONF_PROFILE): unchanged ---
setup
env -u DCONF_PROFILE PATH="$(mock_path)" bash "$MOCK_DIR/ohmydebn-patched.sh" </dev/null >/dev/null 2>&1
assert_contains "from Cinnamon: config still runs with the default profile" "$(cat "$MOCK_CALLS")" "config: DCONF_PROFILE=<unset>"
mock_cleanup

test_summary
