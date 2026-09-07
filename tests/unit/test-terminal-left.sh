#!/bin/bash
#
# Unit tests for bin/ohmydebn-terminal-left's tiling-mode branch: in
# "rules" mode it routes through ohmydebn-terminal-tiled with the
# left-half grid (PID-tracked, no hardcoded title); anything else routes
# through plain ohmydebn-terminal instead, with no forced tiling at all.
# Both ohmydebn-gtile-tiling-mode (pointed at its real repo copy, same
# reasoning as test-launch-tiled.sh) and the two possible downstream
# targets are exercised without a real X session or gTile.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-terminal-left"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-terminal-left ==="

setup_mocks() {
  mock_bin ohmydebn-terminal-tiled <<'EOF'
#!/bin/bash
mock_log "ohmydebn-terminal-tiled GRID=[$OHMYDEBN_TILE_GRID] args=[$*]"
EOF
  mock_bin ohmydebn-terminal <<'EOF'
#!/bin/bash
mock_log "ohmydebn-terminal args=[$*]"
EOF
  sed -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-tiling-mode#$REPO_ROOT/bin/ohmydebn-gtile-tiling-mode#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-terminal-tiled#$MOCK_BIN/ohmydebn-terminal-tiled#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-terminal#$MOCK_BIN/ohmydebn-terminal#g" \
    "$SCRIPT" >"$MOCK_DIR/terminal-left-patched.sh"
}

seed_tiling_mode() {
  local mode="$1"
  mkdir -p "$SCRATCH_HOME/.config/cinnamon/spices/gTile@OhMyDebn"
  printf '{"tiling-mode":{"value":"%s"}}' "$mode" \
    >"$SCRATCH_HOME/.config/cinnamon/spices/gTile@OhMyDebn/gTile@OhMyDebn.json"
}

# Scenario 1: tiling-mode=rules -> routes through ohmydebn-terminal-tiled
# with the left-half grid, args passed straight through.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_tiling_mode "rules"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/terminal-left-patched.sh" --some-arg >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "rules: routes through ohmydebn-terminal-tiled" "$CALLS" "ohmydebn-terminal-tiled"
assert_contains "rules: uses the left-half grid" "$CALLS" "GRID=[2 2 0 0 1 2]"
assert_contains "rules: args passed through" "$CALLS" "args=[--some-arg]"
assert_not_contains "rules: plain ohmydebn-terminal is not used" "$CALLS" "ohmydebn-terminal args="
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: tiling-mode=off -> routes through plain ohmydebn-terminal,
# no forced tiling, args still passed through.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_tiling_mode "off"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/terminal-left-patched.sh" --some-arg >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "off: routes through plain ohmydebn-terminal" "$CALLS" "ohmydebn-terminal args=[--some-arg]"
assert_not_contains "off: ohmydebn-terminal-tiled is never called" "$CALLS" "ohmydebn-terminal-tiled"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: tiling-mode=traditional -> same as off, not just "rules" vs
# "off" - anything other than "rules" must skip the forced left-half tile,
# since traditional/traditional-full have gTile's own binary-tree
# auto-placement running instead.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_tiling_mode "traditional"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/terminal-left-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "traditional: routes through plain ohmydebn-terminal" "$CALLS" "ohmydebn-terminal args=[]"
assert_not_contains "traditional: ohmydebn-terminal-tiled is never called" "$CALLS" "ohmydebn-terminal-tiled"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 4: no gTile settings file at all (very fresh install, or
# ohmydebn-gtile not installed) - must default to the same behavior as
# "off", not error out or default to tiling.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/terminal-left-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "no settings file: routes through plain ohmydebn-terminal" "$CALLS" "ohmydebn-terminal args=[]"
assert_not_contains "no settings file: ohmydebn-terminal-tiled is never called" "$CALLS" "ohmydebn-terminal-tiled"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
