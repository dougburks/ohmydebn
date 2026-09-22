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


# --- the banner itself is unchanged: title right after the fence, nothing else inside ---
OUTPUT=$(env -u OHMYDEBN_RUN_START "$SCRIPT" "Stage title")
TITLE_LINE=$(printf '%s\n' "$OUTPUT" | grep -A1 -m1 '^####' | tail -1)
assert_eq "banner: the line right after the top fence is the bare title (what the update GUI parses)" "Stage title" "$TITLE_LINE"
assert_eq "banner: the closing fence follows the title directly - no timestamp line" "yes" \
  "$([[ "$(printf '%s\n' "$OUTPUT" | grep -A2 -m1 '^####' | tail -1)" =~ ^#+$ ]] && echo yes || echo no)"
assert_eq "banner: exactly two fences" "2" "$(printf '%s\n' "$OUTPUT" | grep -c '^#\{10,\}$')"

# --- the stage timeline: one line per headline in ~/.local/state/ohmydebn-logs when a run start is set ---
SCRATCH_HOME=$(mktemp -d)
LOGS="$SCRATCH_HOME/.local/state/ohmydebn-logs"
START=$((EPOCHSECONDS - 125))
HOME="$SCRATCH_HOME" OHMYDEBN_RUN_START="$START" "$SCRIPT" "First stage" >/dev/null
HOME="$SCRATCH_HOME" OHMYDEBN_RUN_START="$START" "$SCRIPT" "Second stage" >/dev/null
assert_eq "timeline: one line per headline, in order, with clock, elapsed and title" "yes" \
  "$(mapfile -t L <"$LOGS/stages-$START.log"; [[ ${#L[@]} -eq 2 && "${L[0]}" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}\ \ \+02:0[5-7]\ \ First\ stage$ && "${L[1]}" == *"Second stage" ]] && echo yes || echo no)"
assert_eq "timeline: stages-latest.log points at this run" "$LOGS/stages-$START.log" "$(readlink "$LOGS/stages-latest.log")"
assert_not_contains "timeline: the banner on screen carries no stamp" "$(HOME="$SCRATCH_HOME" OHMYDEBN_RUN_START="$START" "$SCRIPT" "Third stage")" "+02:"
# Rotation: older runs beyond the newest ten are removed when a new run starts.
for i in $(seq 1 12); do : >"$LOGS/stages-1000$i.log"; touch -d "2026-01-01 00:$(printf '%02d' "$i"):00" "$LOGS/stages-1000$i.log"; done
HOME="$SCRATCH_HOME" OHMYDEBN_RUN_START=$((START + 1)) "$SCRIPT" "New run" >/dev/null
assert_eq "timeline: at most ten runs kept after a new run starts" "10" "$(ls "$LOGS"/stages-[0-9]*.log | wc -l)"
assert_eq "timeline: the newest run's file is among them" "yes" "$([ -e "$LOGS/stages-$((START + 1)).log" ] && echo yes || echo no)"
# No run start: nothing written, banner unchanged.
rm -rf "$LOGS"
HOME="$SCRATCH_HOME" "$SCRIPT" "Standalone" >/dev/null
assert_eq "no run start: no timeline written" "no" "$([ -d "$LOGS" ] && echo yes || echo no)"
# A malformed run start is ignored, not an error.
OUTPUT=$(HOME="$SCRATCH_HOME" OHMYDEBN_RUN_START="not-a-number" "$SCRIPT" "Stage title" 2>&1); STATUS=$?
assert_eq "malformed run start: still exits 0 and prints the banner" "0:yes" "$STATUS:$([[ "$OUTPUT" == *"Stage title"* ]] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"

test_summary
