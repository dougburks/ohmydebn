#!/bin/bash
#
# Unit tests for the picker-colors backfill block in install/config/theme.sh.
# Upgraders already have ~/.local/state/ohmydebn, so the "default theme is
# set" block never runs ohmydebn-theme-set for them - meaning
# ohmydebn-theme-set-picker (and its ~/.config/ohmydebn/current/picker-colors
# output) was never generated on an install that predates that script.
# ohmydebn-menu-picker silently falls back to a generic default palette when
# that file is missing, so upgraders saw the wrong colors until they next ran
# ohmydebn-theme-set themselves. This backfill, gated by its own
# once-only state marker, resolves colors from the already-active
# current/theme and regenerates just the picker's color file - mirroring the
# fastfetch backfill immediately above it in the same script.
#
# All the OTHER once-only blocks in theme.sh (default theme, omarchy theme
# symlink, aether URL handler, fastfetch backfill) are pre-marked done in
# every scenario below, so only the picker-colors backfill block actually
# runs - isolating it the same way test-spice-vdagent.sh isolates its gate.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/theme.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/theme.sh: picker-colors backfill ==="

setup_mocks() {
  mock_bin ohmydebn-theme-set-colors <<'EOF'
#!/bin/bash
mock_log "theme-set-colors $*"
echo "$MOCK_DIR/resolved-colors.toml"
EOF
  mock_bin ohmydebn-theme-set-picker <<'EOF'
#!/bin/bash
mock_log "theme-set-picker $*"
EOF
  mock_bin ohmydebn-theme-set-colors-delete <<'EOF'
#!/bin/bash
mock_log "theme-set-colors-delete $*"
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/theme-patched.sh"
}

# Marks every OTHER once-only block in theme.sh as already done, so a run
# only ever exercises the picker-colors backfill block under test.
skip_other_once_only_blocks() {
  local home="$1"
  mkdir -p "$home/.local/state/ohmydebn-config"
  touch "$home/.local/state/ohmydebn"
  touch "$home/.local/state/ohmydebn-config/omarchy-theme-symlink-20260325"
  touch "$home/.local/state/ohmydebn-config/omarchy-theme-url-handler-20260814"
  touch "$home/.local/state/ohmydebn-config/fastfetch-config-backfill-20260817"
}

# Scenario 1: upgrader with an already-active theme and no backfill marker
# yet -> colors are resolved from current/theme and handed to the picker,
# and the temp colors source is cleaned up afterward.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
skip_other_once_only_blocks "$SCRATCH_HOME"
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current/theme"
touch "$SCRATCH_HOME/.config/ohmydebn/current/theme/colors.toml"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/theme-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "resolves colors from the active current/theme dir" "$CALLS" \
  "theme-set-colors $SCRATCH_HOME/.config/ohmydebn/current/theme"
assert_contains "passes the resolved colors source to the picker" "$CALLS" \
  "theme-set-picker $MOCK_DIR/resolved-colors.toml"
assert_contains "cleans up the resolved colors source afterward" "$CALLS" \
  "theme-set-colors-delete $MOCK_DIR/resolved-colors.toml"
assert_eq "backfill marker written so this doesn't re-run" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/picker-colors-backfill-20260825" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: backfill marker already present -> nothing runs at all, even
# though a theme is active (the once-only gate still wins, unchanged).
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
skip_other_once_only_blocks "$SCRATCH_HOME"
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/picker-colors-backfill-20260825"
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current/theme"
touch "$SCRATCH_HOME/.config/ohmydebn/current/theme/colors.toml"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/theme-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_eq "already backfilled: nothing called at all" "" "$CALLS"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: no marker yet, but no theme is active (current/theme absent) -
# the backfill must not call out to resolve/write colors for a theme that
# isn't there, but still marks itself done so it doesn't retry forever.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
skip_other_once_only_blocks "$SCRATCH_HOME"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/theme-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_eq "no active theme: nothing called at all" "" "$CALLS"
assert_eq "no active theme: backfill marker still written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/picker-colors-backfill-20260825" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
