#!/bin/bash
#
# Unit tests for bin/ohmydebn-headline. No mocking needed - the script has
# no external dependencies.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-headline"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-headline ==="

OUTPUT=$("$SCRIPT" "Configuring test thing")
assert_contains "1-arg form: prints the message" "$OUTPUT" "Configuring test thing"

# Regression test: an apt upgrade can replace this file mid-update while an
# old, not-yet-upgraded caller is still running and passes the old 2-arg
# (processor, text) form. Must still print the real message, not "cat".
OUTPUT=$("$SCRIPT" "cat" "Configuring test thing")
assert_contains "2-arg form (old callers): prints the real message" "$OUTPUT" "Configuring test thing"
assert_not_contains "2-arg form (old callers): does not print the literal processor arg" "$OUTPUT" $'\ncat\n'


# --- the timestamp line: inside the banner, after the title, never in the title ---
OUTPUT=$(env -u OHMYDEBN_RUN_START "$SCRIPT" "Stage title")
TITLE_LINE=$(printf '%s\n' "$OUTPUT" | grep -A1 -m1 '^####' | tail -1)
assert_eq "banner: the line right after the top fence is the bare title (what the update GUI parses)" "Stage title" "$TITLE_LINE"
STAMP_LINE=$(printf '%s\n' "$OUTPUT" | grep -A2 -m1 '^####' | tail -1)
assert_eq "banner: a clock stamp follows the title" "yes" "$([[ "$STAMP_LINE" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] && echo yes || echo no)"
assert_eq "banner: exactly two fences" "2" "$(printf '%s\n' "$OUTPUT" | grep -c '^#\{10,\}$')"
# ($(...) strips trailing newlines, so the trailing blank is checked on a file.)
env -u OHMYDEBN_RUN_START "$SCRIPT" "Stage title" >"$REPO_ROOT/tests/.headline-out.tmp"
assert_eq "banner: still ends with a blank line (the parser's stage-reset)" "" "$(tail -1 "$REPO_ROOT/tests/.headline-out.tmp")"
rm -f "$REPO_ROOT/tests/.headline-out.tmp"

OUTPUT=$(OHMYDEBN_RUN_START=$((EPOCHSECONDS - 125)) "$SCRIPT" "Stage title")
STAMP_LINE=$(printf '%s\n' "$OUTPUT" | grep -A2 -m1 '^####' | tail -1)
assert_eq "banner: with a run start, the stamp adds elapsed mm:ss" "yes" "$([[ "$STAMP_LINE" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}\ \ \+02:0[5-7]$ ]] && echo yes || echo no)"
OUTPUT=$(OHMYDEBN_RUN_START="not-a-number" "$SCRIPT" "Stage title")
STAMP_LINE=$(printf '%s\n' "$OUTPUT" | grep -A2 -m1 '^####' | tail -1)
assert_eq "banner: a malformed run start just drops the elapsed part" "yes" "$([[ "$STAMP_LINE" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] && echo yes || echo no)"

test_summary
