#!/bin/bash
#
# Unit tests for install/finalization/hotkeys.sh, kept for updates from
# OhMyDebn 4.5.0-4.7.0. When their first `apt update` failed (PackageKit
# holding apt's lock), their ohmydebn-update ran their own old install
# steps, whose full upgrade then installed this release partway through.
# The old run goes on sourcing its finalization/all.sh's files by name, and
# stopped at hotkeys.sh, since renamed keybinding.sh. Now every name it
# sources exists, and hotkeys.sh runs this release's whole install in the
# old run's place. The install and the headline are stand-ins.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/finalization/hotkeys.sh: updates from 4.5.0-4.7.0 ==="

# finalization/all.sh in 4.5.0, 4.6.0 and 4.7.0 sources these, in this
# order, after the full upgrade in updates.sh: each must still exist.
for name in gtile-restart-flag.sh hotkeys.sh lightdm.sh finale.sh; do
  assert_eq "an old release's finalization/all.sh finds $name" "yes" \
    "$([ -f "$REPO_ROOT/install/finalization/$name" ] && echo yes || echo no)"
done

# run <status the new install exits with>: hotkeys.sh sourced as the old
# all.sh does, under set -e, with one more old step after it.
run() {
  mock_init
  printf '#!/bin/bash\nmock_log "headline $*"\n' | mock_bin ohmydebn-headline
  printf '#!/bin/bash\nmock_log "new install ran"\nexit %s\n' "$1" >"$MOCK_DIR/install.sh"
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/share/ohmydebn/install.sh#$MOCK_DIR/install.sh#g" \
    "$REPO_ROOT/install/finalization/hotkeys.sh" >"$MOCK_DIR/hotkeys.sh"
  OUT=$(PATH="$(mock_path)" bash -c 'set -e; source "$1"; echo "old step after it ran"' _ "$MOCK_DIR/hotkeys.sh" </dev/null 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

run 0
assert_contains "says what's happening" "$CALLS" "headline OhMyDebn was upgraded during this update"
assert_contains "runs this release's install" "$CALLS" "new install ran"
assert_not_contains "the old run's later steps don't run" "$OUT" "old step after it ran"
assert_eq "the new install succeeded: the update succeeds" "0" "$STATUS"
mock_cleanup

run 3
assert_eq "the new install failed: the update reports it" "3" "$STATUS"
assert_not_contains "the new install failed: no old steps after it" "$OUT" "old step after it ran"
mock_cleanup

test_summary
