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
# or Cinnamon never reads it. And those files must be copied in before the
# applet list is set: from Linux Mint 27 on, Cinnamon no longer watches a
# loaded applet's settings file, so a copy made after the applets loaded
# was ignored and then overwritten with the defaults (a fresh Mint 27
# install kept the visual workspace switcher). Static checks only; nothing
# is run.

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

CINNAMON_SH="$REPO_ROOT/install/config/cinnamon.sh"
SPICE_COPY_LINE=$(grep -n 'cp -av /usr/share/ohmydebn/config/cinnamon/spices/\$SPICE/' "$CINNAMON_SH" | cut -d: -f1)
APPLET_LIST_LINE=$(grep -n 'gsettings set org.cinnamon enabled-applets' "$CINNAMON_SH" | cut -d: -f1)
assert_eq "the applets' settings are copied before the applets go on the panel" "yes" \
  "$([[ -n "$SPICE_COPY_LINE" && -n "$APPLET_LIST_LINE" && "$SPICE_COPY_LINE" -lt "$APPLET_LIST_LINE" ]] && echo yes || echo no)"

test_summary
