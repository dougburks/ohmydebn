#!/bin/bash
#
# Checks the panel applets install/config/cinnamon.sh seeds into
# org.cinnamon enabled-applets. Each entry is panel:side:position:uuid:id,
# and the instance id must be unique across the whole list: Cinnamon tracks
# applets (and their per-instance settings files) by that id alone, so two
# applets sharing one - network and the workspace switcher both had 10, the
# window list and power both 12 - left a removed applet loaded until
# Cinnamon restarted. Each seeded per-instance settings file
# (config/cinnamon/spices/<uuid>/<id>.json) must also match its applet's id,
# or Cinnamon never reads it. Static checks only; nothing is run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/cinnamon.sh: seeded panel applets ==="

APPLETS=$(grep -o "org.cinnamon enabled-applets \"\[[^]]*\]\"" "$REPO_ROOT/install/config/cinnamon.sh" |
  grep -oE "'[^']+'" | tr -d "'")

assert_eq "the applet list was found" "yes" "$([[ -n "$APPLETS" ]] && echo yes || echo no)"

DUPLICATES=$(cut -d: -f5 <<<"$APPLETS" | sort | uniq -d | tr '\n' ' ')
assert_eq "every applet instance id is unique" "" "$DUPLICATES"

for FILE in "$REPO_ROOT"/config/cinnamon/spices/*@cinnamon.org/[0-9]*.json; do
  [[ -e "$FILE" ]] || continue
  UUID=$(basename "$(dirname "$FILE")")
  ID=$(basename "$FILE" .json)
  assert_contains "$UUID/$ID.json matches a seeded $UUID instance" "$APPLETS" "$UUID:$ID"
done

test_summary
