#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-colors-delete. It deletes the
# temporary colors file ohmydebn-theme-set-colors made with mktemp, and
# never a theme's own file. mktemp honors $TMPDIR, but this only looked in
# /tmp, so with TMPDIR set the file was left behind on every theme switch.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-colors-delete ==="

mock_init
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-colors-delete"
mkdir -p "$MOCK_DIR/theme"
# A TMPDIR outside /tmp, as it would be when set.
ALT_TMP=$(mktemp -d -p /var/tmp)
exists() { [ -e "$1" ] && echo yes || echo no; }

TEMP=$(TMPDIR="$ALT_TMP" mktemp)
TMPDIR="$ALT_TMP" bash "$SCRIPT" "$TEMP" </dev/null
assert_eq "TMPDIR set: the temporary colors file is deleted" "no" "$(exists "$TEMP")"

TEMP=$(TMPDIR="$ALT_TMP/" mktemp)
TMPDIR="$ALT_TMP/" bash "$SCRIPT" "$TEMP" </dev/null
assert_eq "TMPDIR with a trailing slash: deleted too" "no" "$(exists "$TEMP")"

: >"$MOCK_DIR/theme/colors.toml"
TMPDIR="$ALT_TMP" bash "$SCRIPT" "$MOCK_DIR/theme/colors.toml" </dev/null
assert_eq "a theme's own colors file is never deleted" "yes" "$(exists "$MOCK_DIR/theme/colors.toml")"

TEMP=$(env -u TMPDIR mktemp)
env -u TMPDIR bash "$SCRIPT" "$TEMP" </dev/null
assert_eq "no TMPDIR: the file in /tmp is deleted" "no" "$(exists "$TEMP")"
rm -f "$TEMP"

rm -rf "$ALT_TMP"
mock_cleanup
test_summary
