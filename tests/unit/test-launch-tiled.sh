#!/bin/bash
#
# Unit tests for bin/ohmydebn-launch-tiled's active-window poll, in
# particular OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN - added after a live-VM
# report caught the first attempt at this exclude logic actually
# excluding the wrong window (the caller's own ID, already redundant
# with PREV_WIN, instead of the window that transiently regains focus
# when the caller closes). A mocked xdotool that returns a scripted
# sequence of "active window" values per call - via a counter over its
# own call log, since ohmydebn-launch-tiled polls it repeatedly - lets
# this be verified without a real X session or gTile.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-launch-tiled"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-launch-tiled ==="

# xdotool getactivewindow returns, per call (1-indexed): 111 (the true
# PREV_WIN, captured once at the top), then 222 twice (simulating a
# caller window that transiently regains focus while closing), then 333
# forever after (the real launched app's window). ohmydebn-gtile-apply
# and sleep are mocked too - the former to record what it was actually
# called with instead of really talking to gTile over DBus, the latter
# so the poll loop's real 0.1s waits don't slow the test down.
setup_mocks() {
  mock_bin xdotool <<EOF
#!/bin/bash
if [ "\$1" = "getactivewindow" ]; then
  N=\$(( \$(grep -c '^xdotool getactivewindow\$' "\$MOCK_CALLS") + 1 ))
  echo "xdotool \$*" >> "\$MOCK_CALLS"
  case "\$N" in
    1) echo "111" ;;
    2|3) echo "222" ;;
    *) echo "333" ;;
  esac
else
  echo "xdotool \$*" >> "\$MOCK_CALLS"
fi
EOF
  mock_bin ohmydebn-gtile-apply <<'EOF'
#!/bin/bash
echo "ohmydebn-gtile-apply $*" >> "$MOCK_CALLS"
EOF
  mock_bin ohmydebn-gtile-hide <<'EOF'
#!/bin/bash
echo "ohmydebn-gtile-hide $*" >> "$MOCK_CALLS"
EOF
  mock_bin sleep <<'EOF'
#!/bin/bash
exit 0
EOF
  mock_bin fake-app <<'EOF'
#!/bin/bash
echo "fake-app ran" >> "$MOCK_CALLS"
exit 0
EOF
  # ohmydebn-gtile-tiling-mode is pointed at its real repo copy, not a
  # mock - it's a pure read of $HOME's own settings file (already scoped
  # to SCRATCH_HOME below via seed_tiling_mode), so exercising the actual
  # implementation is both simpler and better coverage than reimplementing
  # its jq logic a second time in a stub.
  sed -e "s#/usr/bin/xdotool#$MOCK_BIN/xdotool#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-apply#$MOCK_BIN/ohmydebn-gtile-apply#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-hide#$MOCK_BIN/ohmydebn-gtile-hide#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-tiling-mode#$REPO_ROOT/bin/ohmydebn-gtile-tiling-mode#g" \
    -e "s#/usr/bin/sleep#$MOCK_BIN/sleep#g" \
    "$SCRIPT" >"$MOCK_DIR/launch-tiled-patched.sh"
}

# Every scenario below is testing the poll/exclude logic, which only runs
# at all in "rules" mode - so HOME has to point at a scratch dir seeded
# with a controlled gTile@OhMyDebn.json forcing that, rather than falling
# through to whatever $HOME actually is on the machine running these
# tests. Without this, the tests were silently reading *this developer's
# own* real gTile settings file and only passing because that happened to
# already be "rules" - the exact class of ambient-environment leak
# test-gtile-restart-flag.sh/test-keybinding-restart-flag.sh had with
# OHMYDEBN_CINNAMON_RESTART_NEEDED.
seed_tiling_mode() {
  local mode="$1"
  mkdir -p "$SCRATCH_HOME/.config/cinnamon/spices/gTile@OhMyDebn"
  printf '{"tiling-mode":{"value":"%s"}}' "$mode" \
    >"$SCRATCH_HOME/.config/cinnamon/spices/gTile@OhMyDebn/gTile@OhMyDebn.json"
}

# Scenario 1: no EXCLUDE_WIN set (every existing caller except
# ohmydebn-menu/ohmydebn-theme-carousel) - unchanged old behavior, the
# first window that differs from PREV_WIN (111) is accepted immediately,
# even though here that's "222", the window this whole mechanism exists
# to NOT tile once a caller sets the exclude var.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_tiling_mode "rules"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 0 0 1 2 -- fake-app >/dev/null 2>&1
assert_contains "no EXCLUDE_WIN: tiles the first window that differs from PREV_WIN" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 222 2 2 0 0 1 2"
assert_contains "no EXCLUDE_WIN: hides window 222 as soon as it's found, before tiling it" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-hide 222"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: EXCLUDE_WIN=222 - the regression this test exists for. The
# poll must skip 222 (checked on every iteration, not just once) and
# keep waiting for 333, the actual launched app's window.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_tiling_mode "rules"
OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN=222 HOME="$SCRATCH_HOME" PATH="$(mock_path)" \
  bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 1 0 1 2 -- fake-app >/dev/null 2>&1
assert_contains "EXCLUDE_WIN=222: never tiles 222" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 333 2 2 1 0 1 2"
assert_not_contains "EXCLUDE_WIN=222: gtile-apply never called with 222 as the window ID" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 222 "
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: EXCLUDE_WIN equal to PREV_WIN itself (111) - the common
# case in practice (ohmydebn-menu/theme-carousel capture "whatever was
# active before I existed", which is often unchanged by the time
# ohmydebn-launch-tiled's own PREV_WIN capture runs) - must not somehow
# short-circuit the whole loop or misbehave; 111 was never going to be
# accepted anyway (already excluded via PREV_WIN), so behavior should be
# identical to scenario 1.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_tiling_mode "rules"
OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN=111 HOME="$SCRATCH_HOME" PATH="$(mock_path)" \
  bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 0 0 2 2 -- fake-app >/dev/null 2>&1
assert_contains "EXCLUDE_WIN==PREV_WIN: still tiles the first genuinely different window" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 222 2 2 0 0 2 2"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 4: usage error - unchanged by this change, still worth locking
# in given the poll logic above got touched.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_tiling_mode "rules"
OUTPUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 0 0 1 2 2>&1)
STATUS=$?
assert_contains "missing '--' separator: usage error" "$OUTPUT" "Usage:"
assert_eq "missing '--' separator: nonzero exit" "1" "$STATUS"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 5: tiling-mode is "off" (the schema's own default) - the new
# gate this change adds. The command must still run, but neither
# gtile-hide nor gtile-apply should ever be called, and the poll loop
# shouldn't run at all (no wasted xdotool/sleep calls burning through the
# ~5s timeout for nothing).
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_tiling_mode "off"
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 0 0 1 2 -- fake-app >/dev/null 2>&1
# This path backgrounds fake-app and returns immediately, with no poll
# loop to implicitly wait out - unlike the scenarios above, so a brief
# sleep here is the only thing standing between this and a real race
# against the backgrounded mock's own write to $MOCK_CALLS.
sleep 0.1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "tiling-mode=off: the launched command still runs" "$CALLS" "fake-app ran"
assert_not_contains "tiling-mode=off: gtile-apply is never called" "$CALLS" "ohmydebn-gtile-apply"
assert_not_contains "tiling-mode=off: gtile-hide is never called" "$CALLS" "ohmydebn-gtile-hide"
assert_not_contains "tiling-mode=off: doesn't even poll xdotool" "$CALLS" "xdotool getactivewindow"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 6: no gTile settings file at all (very fresh install, or
# ohmydebn-gtile not installed) - must default to the same behavior as
# "off", not error out or (worse) default to tiling.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 0 0 1 2 -- fake-app >/dev/null 2>&1
sleep 0.1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "no settings file: the launched command still runs" "$CALLS" "fake-app ran"
assert_not_contains "no settings file: gtile-apply is never called" "$CALLS" "ohmydebn-gtile-apply"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
