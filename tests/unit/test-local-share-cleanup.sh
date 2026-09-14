#!/bin/bash
#
# Unit tests for install/cleanup/local-share.sh. Covers the "remove old
# directories" loop - including its developer-override guard: a SYMLINK
# at ~/.local/share/cinnamon/extensions/gTile@OhMyDebn is someone
# pointing Cinnamon at a local working copy of the extension (the user
# dir shadows the packaged copy in /usr/share), and the cleanup used to
# delete it on every update, silently swapping the dev copy for the
# packaged one ([ -d ] is true for a symlink to a directory, so the
# guard needs an explicit [ -L ] check first; bit the gTile dev
# workflow three times in one day before the guard existed) - and the
# legacy-aether-desktop-file loop: a per-user
# ~/.local/share/applications/{aether-protocol-handler,li.oever.aether.url-handler}.desktop
# left over from before ohmydebn-aether-url-guard existed (or from an
# older per-user packaging of the guarded one) shadows - or, absent an
# explicit mimeapps.list default, is preferred over - the guarded
# system-wide /usr/share/applications/li.oever.aether.url-handler.desktop,
# silently routing aether:// links straight to aether with no confirmation
# prompt.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/cleanup/local-share.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/cleanup/local-share.sh ==="

# Scenario 1: both legacy aether desktop files present -> both removed,
# a legitimate unrelated desktop file is left alone.
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/share/applications"
touch "$SCRATCH_HOME/.local/share/applications/aether-protocol-handler.desktop"
touch "$SCRATCH_HOME/.local/share/applications/li.oever.aether.url-handler.desktop"
touch "$SCRATCH_HOME/.local/share/applications/some-other-app.desktop"
HOME="$SCRATCH_HOME" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "aether-protocol-handler.desktop removed" "no" \
  "$([ -f "$SCRATCH_HOME/.local/share/applications/aether-protocol-handler.desktop" ] && echo yes || echo no)"
assert_eq "per-user li.oever.aether.url-handler.desktop removed" "no" \
  "$([ -f "$SCRATCH_HOME/.local/share/applications/li.oever.aether.url-handler.desktop" ] && echo yes || echo no)"
assert_eq "unrelated desktop file left alone" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/share/applications/some-other-app.desktop" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"

# Scenario 2: neither legacy file present -> no-op, no error, nothing else
# in the directory is touched.
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/share/applications"
touch "$SCRATCH_HOME/.local/share/applications/some-other-app.desktop"
HOME="$SCRATCH_HOME" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "neither present: exits cleanly" "0" "$?"
assert_eq "neither present: unrelated file untouched" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/share/applications/some-other-app.desktop" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"

# Scenario 3: pre-existing "old directory" cleanup still works (no
# regression from the addition above) - a stale ~/.local/share/ohmydebn
# directory from an old install approach gets removed.
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/share/ohmydebn/some-file-inside"
HOME="$SCRATCH_HOME" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "old ~/.local/share/ohmydebn directory removed" "no" \
  "$([ -d "$SCRATCH_HOME/.local/share/ohmydebn" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"

# Scenario 4: nothing at all to clean up -> script still exits 0 (no `set
# -e`/missing-directory failure from the applications/ dir not existing).
SCRATCH_HOME=$(mktemp -d)
HOME="$SCRATCH_HOME" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "nothing to clean up: exits cleanly" "0" "$?"
rm -rf "$SCRATCH_HOME"

# Scenario 5: a SYMLINKED gTile extension dir is a developer override -
# it survives, its target is untouched, and the script says why.
SCRATCH_HOME=$(mktemp -d)
DEV_CHECKOUT="$SCRATCH_HOME/dev-checkout"
mkdir -p "$DEV_CHECKOUT/5.4"
echo "dev code" > "$DEV_CHECKOUT/5.4/gTile.js"
mkdir -p "$SCRATCH_HOME/.local/share/cinnamon/extensions"
ln -s "$DEV_CHECKOUT" "$SCRATCH_HOME/.local/share/cinnamon/extensions/gTile@OhMyDebn"
OUTPUT=$(HOME="$SCRATCH_HOME" bash "$SCRIPT" 2>&1)
assert_eq "symlinked gTile extension dir survives" "yes" \
  "$([ -L "$SCRATCH_HOME/.local/share/cinnamon/extensions/gTile@OhMyDebn" ] && echo yes || echo no)"
assert_eq "the symlink's target (the dev checkout) is untouched" "yes" \
  "$([ -f "$DEV_CHECKOUT/5.4/gTile.js" ] && echo yes || echo no)"
assert_contains "announces the developer override" "$OUTPUT" "developer override"
rm -rf "$SCRATCH_HOME"

# Scenario 6: a REAL (non-symlink) directory at the gTile extension path
# is a stale per-user copy from the old install approach - still removed,
# so the guard didn't neuter the cleanup's actual job.
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/share/cinnamon/extensions/gTile@OhMyDebn/5.4"
HOME="$SCRATCH_HOME" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "a real per-user gTile extension dir is still removed" "no" \
  "$([ -d "$SCRATCH_HOME/.local/share/cinnamon/extensions/gTile@OhMyDebn" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"

test_summary
