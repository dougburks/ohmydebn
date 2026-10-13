#!/bin/bash
#
# Unit tests for bin/ohmydebn-socrates-cleanup. It keeps the newest
# SO-CRATES image and, now, also the one ohmydebn-socrates-run starts by
# default (pinned by digest): after a run of another tag, that default
# used to be removed as "older", so the next normal launch downloaded it
# all over again. podman is a stand-in with a fixed image list that logs
# every removal.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-socrates-cleanup"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-socrates-cleanup ==="

# Both scripts name the same default image.
RUN_DEFAULT=$(sed -n 's/^DEFAULT_IMAGE="\$IMAGE_REPO@\(sha256:[0-9a-f]*\)"$/\1/p' "$REPO_ROOT/bin/ohmydebn-socrates-run")
CLEANUP_DEFAULT=$(sed -n 's/^DEFAULT_IMAGE="\$IMAGE_PREFIX@\(sha256:[0-9a-f]*\)"$/\1/p' "$SCRIPT")
assert_eq "the default image is the same one ohmydebn-socrates-run starts" "$RUN_DEFAULT" "$CLEANUP_DEFAULT"
assert_contains "...and was found" "$RUN_DEFAULT" "sha256:"

# setup <full ID the default image has, or empty if it isn't here>
setup() {
  mock_init
  echo "$1" >"$MOCK_DIR/default-id"
  mock_bin podman <<'STUB'
#!/bin/bash
case "$1 $2" in
"images "*)
  echo "2026-10-01 10:00:00|aaaaaaaaaaaa|ghcr.io/dougburks/so-crates:newer"
  echo "2026-09-01 10:00:00|bbbbbbbbbbbb|ghcr.io/dougburks/so-crates:<none>"
  echo "2026-08-01 10:00:00|cccccccccccc|ghcr.io/dougburks/so-crates:old"
  ;;
"image inspect")
  [[ -s "$MOCK_DIR/default-id" ]] || exit 125
  cat "$MOCK_DIR/default-id"
  ;;
"inspect "*) echo "$4" ;;
"container ls") ;;
"rmi "*) mock_log "rmi $2" ;;
esac
STUB
}
run() { OUTPUT=$(PATH="$(mock_path)" bash "$SCRIPT" "$@" </dev/null 2>&1); STATUS=$?; CALLS=$(cat "$MOCK_CALLS"); }

setup "bbbbbbbbbbbb$(printf '0%.0s' {1..52})"
run --force
assert_eq "exits 0" "0" "$STATUS"
assert_not_contains "the newest image is kept" "$CALLS" "rmi aaaaaaaaaaaa"
assert_not_contains "the default image is kept, though older" "$CALLS" "rmi bbbbbbbbbbbb"
assert_contains "other older images are removed" "$CALLS" "rmi cccccccccccc"
assert_contains "says it keeps the default" "$OUTPUT" "the one SO-CRATES starts by default"
mock_cleanup

setup ""
run --force
assert_contains "default image not downloaded: older images go as before" "$CALLS" "rmi bbbbbbbbbbbb"
mock_cleanup

setup ""
run --bogus
assert_eq "an unknown option is an error" "1" "$STATUS"
mock_cleanup

test_summary
