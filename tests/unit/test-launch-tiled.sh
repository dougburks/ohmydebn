#!/bin/bash
#
# Unit tests for the launchers that open a window already tiled:
# bin/ohmydebn-gtile-tile-next (asks gTile's TileNextWindow to tile the
# next new window), bin/ohmydebn-launch-tiled and
# bin/ohmydebn-terminal-tiled, which call it before starting their app.
#
# They used to start the app, then poll xdotool for the window that took
# focus and tile that. xdotool only sees X11 windows, so in Cinnamon's
# Wayland session Brave, Nemo and other Wayland apps opened untiled in
# the middle of the screen (Linux Mint 27). gdbus and the app are
# stand-ins that log, so no gTile or display is needed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-gtile-tile-next, -launch-tiled, -terminal-tiled ==="

setup_mocks() {
  mock_bin gdbus <<'EOF'
#!/bin/bash
mock_log "gdbus $*"
exit "${MOCK_GDBUS_EXIT:-0}"
EOF
  mock_bin xdotool <<'EOF'
#!/bin/bash
mock_log "xdotool $*"
EOF
  mock_bin fake-app <<'EOF'
#!/bin/bash
mock_log "fake-app ran $*"
EOF
  mock_bin ohmydebn-alacritty <<'EOF'
#!/bin/bash
mock_log "ohmydebn-alacritty $*"
EOF
  local script
  for script in ohmydebn-gtile-tile-next ohmydebn-launch-tiled ohmydebn-terminal-tiled; do
    # ohmydebn-gtile-tiling-mode is its real repo copy: a pure read of
    # $HOME's gTile settings file, seeded per scenario below.
    sed -e "s#/usr/bin/gdbus#$MOCK_BIN/gdbus#g" \
      -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-tile-next#$MOCK_DIR/ohmydebn-gtile-tile-next#g" \
      -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-tiling-mode#$REPO_ROOT/bin/ohmydebn-gtile-tiling-mode#g" \
      -e "s#/usr/share/ohmydebn/bin/ohmydebn-alacritty#$MOCK_BIN/ohmydebn-alacritty#g" \
      "$REPO_ROOT/bin/$script" >"$MOCK_DIR/$script"
    chmod +x "$MOCK_DIR/$script"
  done
  SCRATCH_HOME="$MOCK_DIR/home"
  mkdir -p "$SCRATCH_HOME"
}

# A HOME of its own with gTile's tiling mode set, rather than whatever the
# machine running the tests has.
seed_tiling_mode() {
  mkdir -p "$SCRATCH_HOME/.config/cinnamon/spices/gTile@OhMyDebn"
  printf '{"tiling-mode":{"value":"%s"}}' "$1" \
    >"$SCRATCH_HOME/.config/cinnamon/spices/gTile@OhMyDebn/gTile@OhMyDebn.json"
}

# run <script> [args...]: the script under test, its output in OUTPUT,
# its exit status in STATUS, and what it called in CALLS. The launched app
# runs in the background, so CALLS waits until it has logged.
run() {
  OUTPUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/$1" "${@:2}" 2>&1 </dev/null)
  STATUS=$?
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -q "fake-app ran\|ohmydebn-alacritty" "$MOCK_CALLS" 2>/dev/null && break
    sleep 0.05
  done
  CALLS=$(cat "$MOCK_CALLS" 2>/dev/null)
}

TILE_NEXT_CALL="gdbus call --session --dest org.gTile.Control --object-path /org/gTile/Control --method org.gTile.Control.TileNextWindow"

# --- ohmydebn-gtile-tile-next ---
mock_init
setup_mocks
run ohmydebn-gtile-tile-next 2 2 1 0 1 2
assert_eq "tile-next: succeeds" "0" "$STATUS"
assert_contains "tile-next: asks gTile for the next window, the grid, then a timeout" "$CALLS" "$TILE_NEXT_CALL 2 2 1 0 1 2 5000"
mock_cleanup

mock_init
setup_mocks
run ohmydebn-gtile-tile-next 2 2 1 0
assert_eq "tile-next: a short grid is a usage error" "1" "$STATUS"
assert_contains "tile-next: says how to use it" "$OUTPUT" "Usage:"
assert_not_contains "tile-next: and asks gTile nothing" "$CALLS" "TileNextWindow"
mock_cleanup

# --- ohmydebn-launch-tiled ---
# "rules" mode: gTile is asked first, then the app starts.
mock_init
setup_mocks
seed_tiling_mode rules
run ohmydebn-launch-tiled 2 2 1 0 1 2 -- fake-app --flag
assert_eq "rules: exits 0" "0" "$STATUS"
assert_contains "rules: asks gTile to tile the next window there" "$CALLS" "$TILE_NEXT_CALL 2 2 1 0 1 2 5000"
assert_contains "rules: starts the app with its arguments" "$CALLS" "fake-app ran --flag"
assert_eq "rules: gTile is asked before the app starts" "TileNextWindow fake-app" \
  "$(grep -o 'TileNextWindow\|fake-app' <<<"$CALLS" | head -2 | tr '\n' ' ' | sed 's/ $//')"
assert_not_contains "rules: no xdotool (it never sees Wayland windows)" "$CALLS" "xdotool"
mock_cleanup

# gTile not answering (an older gTile, or disabled): the app still opens.
mock_init
setup_mocks
seed_tiling_mode rules
MOCK_GDBUS_EXIT=1 run ohmydebn-launch-tiled 2 2 0 0 2 2 -- fake-app
assert_eq "gTile not answering: exits 0" "0" "$STATUS"
assert_contains "gTile not answering: the app still starts" "$CALLS" "fake-app ran"
mock_cleanup

# Other modes: gTile places new windows itself, and "off" promises
# nothing is tiled automatically.
for mode in off traditional scrollable; do
  mock_init
  setup_mocks
  seed_tiling_mode "$mode"
  run ohmydebn-launch-tiled 2 2 0 0 1 2 -- fake-app
  assert_contains "$mode: the app starts" "$CALLS" "fake-app ran"
  assert_not_contains "$mode: gTile isn't asked to tile it" "$CALLS" "TileNextWindow"
  mock_cleanup
done

# No gTile settings file at all (a fresh install): same as "off".
mock_init
setup_mocks
run ohmydebn-launch-tiled 2 2 0 0 1 2 -- fake-app
assert_contains "no settings file: the app starts" "$CALLS" "fake-app ran"
assert_not_contains "no settings file: gTile isn't asked to tile it" "$CALLS" "TileNextWindow"
mock_cleanup

mock_init
setup_mocks
seed_tiling_mode rules
run ohmydebn-launch-tiled 2 2 0 0 1 2
assert_contains "missing '--' separator: usage error" "$OUTPUT" "Usage:"
assert_eq "missing '--' separator: nonzero exit" "1" "$STATUS"
mock_cleanup

# --- ohmydebn-terminal-tiled ---
# Tiles in any mode, as it always has: its callers ask for it explicitly.
mock_init
setup_mocks
seed_tiling_mode off
run ohmydebn-terminal-tiled --title 'OhMyDebn Demo' -e demo
assert_contains "terminal: full screen by default" "$CALLS" "$TILE_NEXT_CALL 2 2 0 0 2 2 5000"
assert_contains "terminal: Alacritty gets the arguments" "$CALLS" "ohmydebn-alacritty --title OhMyDebn Demo -e demo"
mock_cleanup

mock_init
setup_mocks
OHMYDEBN_TILE_GRID="2 2 0 0 1 2" run ohmydebn-terminal-tiled
assert_contains "terminal: OHMYDEBN_TILE_GRID picks another grid" "$CALLS" "$TILE_NEXT_CALL 2 2 0 0 1 2 5000"
mock_cleanup

mock_init
setup_mocks
MOCK_GDBUS_EXIT=1 run ohmydebn-terminal-tiled
assert_contains "terminal, gTile not answering: Alacritty still opens" "$CALLS" "ohmydebn-alacritty"
mock_cleanup

test_summary
