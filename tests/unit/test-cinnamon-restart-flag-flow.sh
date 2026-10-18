#!/bin/bash
#
# Unit tests for how a Cinnamon restart request travels through a whole
# ohmydebn.sh run. Steps set OHMYDEBN_CINNAMON_RESTART_NEEDED instead of
# restarting Cinnamon, and finalization/finale.sh does the one restart at
# the end. Config steps ask for it too (config/cinnamon.sh's gTile checkbox
# fix, config/cinnamon-applet-ids.sh), but finalization/all.sh used to clear
# the flag before its own steps ran, so their requests never reached
# finale.sh: an update that renumbered the panel's applets left two network
# icons until the next login. The flag is now cleared once, at the top of
# ohmydebn.sh.
#
# The real ohmydebn.sh and finalization/all.sh run against a scratch
# install tree whose steps are stand-ins, so nothing real is touched.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== Cinnamon restart request through ohmydebn.sh ==="

# setup <config phase stand-in body>
setup() {
  mock_init
  INSTALL="$MOCK_DIR/install"
  mkdir -p "$INSTALL"/{packaging,config,cleanup,finalization}
  : >"$INSTALL/packaging/all.sh"
  printf '%s\n' "$1" >"$INSTALL/config/all.sh"
  : >"$INSTALL/cleanup/all.sh"
  cp "$REPO_ROOT/install/finalization/all.sh" "$INSTALL/finalization/all.sh"
  # Every step finalization/all.sh sources is a stand-in; finale.sh reports
  # whether a restart was asked for.
  grep -oE 'finalization/[A-Za-z0-9._-]+\.sh' "$INSTALL/finalization/all.sh" | sort -u |
    while read -r step; do : >"$INSTALL/$step"; done
  echo 'echo "restart requested: ${OHMYDEBN_CINNAMON_RESTART_NEEDED:-no}"' >"$INSTALL/finalization/finale.sh"
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 0
STUB
  sed "s#^OHMYDEBN_INSTALL=.*#OHMYDEBN_INSTALL=$INSTALL#" "$REPO_ROOT/ohmydebn.sh" >"$MOCK_DIR/ohmydebn.sh"
}

# run [leftover value of the flag in the environment]
run() {
  OUTPUT=$(OHMYDEBN_CINNAMON_RESTART_NEEDED="${1:-}" PATH="$(mock_path)" bash -e "$MOCK_DIR/ohmydebn.sh" </dev/null 2>&1)
}

setup 'export OHMYDEBN_CINNAMON_RESTART_NEEDED=1'
run
assert_eq "a config step's restart request reaches finale.sh" "restart requested: 1" "$OUTPUT"
mock_cleanup

setup ':'
run 1
assert_eq "a value left in the environment doesn't cause a restart nothing asked for" "restart requested: no" "$OUTPUT"
mock_cleanup

# The stand-ins above must cover what really runs, or the test proves
# nothing: finale.sh is sourced by finalization/all.sh, after every step
# that can ask for a restart.
FINAL_STEPS=$(grep -oE 'finalization/[A-Za-z0-9._-]+\.sh' "$REPO_ROOT/install/finalization/all.sh")
assert_contains "finalization/all.sh runs finale.sh" "$FINAL_STEPS" "finalization/finale.sh"
assert_eq "finale.sh runs after gtile-restart-flag.sh" "yes" \
  "$(grep -q 'finale.sh' <<<"$(grep -A99 'gtile-restart-flag.sh' <<<"$FINAL_STEPS")" && echo yes || echo no)"

test_summary
