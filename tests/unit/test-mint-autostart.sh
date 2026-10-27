#!/bin/bash
#
# Unit tests for install/config/mint-autostart.sh: on Linux Mint (and only
# there) it hides Mint's own autostart apps once. It used install.sh's $ID,
# which is empty when ohmydebn-reset-config runs ohmydebn.sh directly, so
# it now reads os-release itself. HOME is a scratch directory and
# OHMYDEBN_TEST_OS_RELEASE a stand-in os-release; nothing in /etc/xdg is
# read for the apps (none exist there in the test), so only the one-time
# marker and the headline are checked.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/mint-autostart.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/mint-autostart.sh ==="

MARKER=.local/state/ohmydebn-config/mint-autostart-20260902

# run <os-release ID>: the step as ohmydebn.sh sources it, with no $ID set
# by anyone (as under ohmydebn-reset-config).
run() {
  mock_init
  H="$MOCK_DIR/home"; mkdir -p "$H"
  printf 'ID=%s\n' "$1" >"$MOCK_DIR/os-release"
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/step.sh"
  env -u ID HOME="$H" PATH="$(mock_path)" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" \
    bash -c 'source "$1"' _ "$MOCK_DIR/step.sh" </dev/null >/dev/null 2>&1
}

run linuxmint
assert_contains "Mint, no \$ID from install.sh: the step still runs" "$(cat "$MOCK_CALLS")" "Disabling unneeded Mint autostart apps"
assert_eq "Mint: the one-time marker is written" "yes" "$([ -f "$H/$MARKER" ] && echo yes || echo no)"
mock_cleanup

run debian
assert_eq "not Mint: nothing runs" "" "$(cat "$MOCK_CALLS")"
assert_eq "not Mint: no marker" "no" "$([ -f "$H/$MARKER" ] && echo yes || echo no)"
mock_cleanup

test_summary
