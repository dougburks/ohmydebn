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

test_summary
