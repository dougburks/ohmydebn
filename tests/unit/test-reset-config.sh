#!/bin/bash
#
# Unit tests for bin/ohmydebn-reset-config: it backs up the config files it
# resets, clears OhMyDebn's state markers so the config layer runs as on a
# new install, and reruns that layer. The update logs survive (they're what
# to look at if the reset goes wrong), and the config layer runs with
# errexit, as install.sh runs it - a failed step used to be skipped and the
# reset carried on half done.
#
# HOME is a scratch directory and ohmydebn.sh is a scratch stand-in, so
# nothing here touches the real config or runs the real config layer.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-reset-config ==="

# setup <stand-in ohmydebn.sh body>
setup() {
  mock_init
  H="$MOCK_DIR/home"
  mkdir -p "$H/.local/state/ohmydebn-config" "$H/.local/state/ohmydebn-logs" "$H/.local/state/ohmydebn-ufw" "$H/.config/btop"
  : >"$H/.local/state/ohmydebn"
  echo log >"$H/.local/state/ohmydebn-logs/update-1.log"
  echo mine >"$H/.config/btop/btop.conf"
  printf '%s\n' "$1" >"$MOCK_DIR/ohmydebn.sh"
  sed "s#/usr/share/ohmydebn/ohmydebn.sh#$MOCK_DIR/ohmydebn.sh#" \
    "$REPO_ROOT/bin/ohmydebn-reset-config" >"$MOCK_DIR/reset"
}

run() {
  OUTPUT=$(HOME="$H" bash "$MOCK_DIR/reset" <<<"" 2>&1)
  STATUS=$?
}

setup 'echo "config layer ran"'
run
assert_eq "reset: exits 0" "0" "$STATUS"
assert_contains "reset: reruns the config layer" "$OUTPUT" "config layer ran"
assert_eq "reset: state markers cleared" "" \
  "$(find "$H/.local/state" -mindepth 1 -maxdepth 1 -name 'ohmydebn*' ! -name ohmydebn-logs)"
assert_eq "reset: update logs kept" "log" "$(cat "$H/.local/state/ohmydebn-logs/update-1.log" 2>/dev/null)"
assert_eq "reset: btop config backed up" "mine" "$(cat "$H"/.config/btop-backup-*/btop.conf 2>/dev/null)"
mock_cleanup

# A step that fails stops the config layer, as it does under install.sh.
setup 'false
echo "carried on after a failed step"'
run
assert_not_contains "failed step: the config layer stops there" "$OUTPUT" "carried on after a failed step"
assert_eq "failed step: reset exits non-zero" "1" "$STATUS"
mock_cleanup

test_summary
