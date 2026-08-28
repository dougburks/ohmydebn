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
WATCH_SECOND_SCRIPT="$REPO_ROOT/bin/ohmydebn-launch-tiled-watch-second"
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
  mock_bin sleep <<'EOF'
#!/bin/bash
exit 0
EOF
  mock_bin fake-app <<'EOF'
#!/bin/bash
exit 0
EOF
  sed -e "s#/usr/bin/xdotool#$MOCK_BIN/xdotool#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-apply#$MOCK_BIN/ohmydebn-gtile-apply#g" \
    -e "s#/usr/bin/sleep#$MOCK_BIN/sleep#g" \
    "$SCRIPT" >"$MOCK_DIR/launch-tiled-patched.sh"
}

# Scenario 1: no EXCLUDE_WIN set (every existing caller except
# ohmydebn-menu/ohmydebn-theme-carousel) - unchanged old behavior, the
# first window that differs from PREV_WIN (111) is accepted immediately,
# even though here that's "222", the window this whole mechanism exists
# to NOT tile once a caller sets the exclude var.
mock_init
setup_mocks
PATH="$(mock_path)" bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 0 0 1 2 -- fake-app >/dev/null 2>&1
assert_contains "no EXCLUDE_WIN: tiles the first window that differs from PREV_WIN" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 222 2 2 0 0 1 2"
mock_cleanup

# Scenario 2: EXCLUDE_WIN=222 - the regression this test exists for. The
# poll must skip 222 (checked on every iteration, not just once) and
# keep waiting for 333, the actual launched app's window.
mock_init
setup_mocks
OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN=222 PATH="$(mock_path)" \
  bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 1 0 1 2 -- fake-app >/dev/null 2>&1
assert_contains "EXCLUDE_WIN=222: never tiles 222" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 333 2 2 1 0 1 2"
assert_not_contains "EXCLUDE_WIN=222: gtile-apply never called with 222 as the window ID" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 222 "
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
OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN=111 PATH="$(mock_path)" \
  bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 0 0 2 2 -- fake-app >/dev/null 2>&1
assert_contains "EXCLUDE_WIN==PREV_WIN: still tiles the first genuinely different window" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 222 2 2 0 0 2 2"
mock_cleanup

# Scenario 4: usage error - unchanged by this change, still worth locking
# in given the poll logic above got touched.
mock_init
setup_mocks
OUTPUT=$(PATH="$(mock_path)" bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 0 0 1 2 2>&1)
STATUS=$?
assert_contains "missing '--' separator: usage error" "$OUTPUT" "Usage:"
assert_eq "missing '--' separator: nonzero exit" "1" "$STATUS"
mock_cleanup

# xdotool sequence for the WATCH_SECOND scenarios below: 111 (PREV_WIN),
# then 222 (the first window - e.g. a dpkg-gated launcher's floating
# install-presentation terminal) three times in a row (simulating
# installation still running while the background watcher polls), then
# 444 forever after (the real app's own, later window).
setup_mocks_second_window() {
  mock_bin xdotool <<EOF
#!/bin/bash
if [ "\$1" = "getactivewindow" ]; then
  N=\$(( \$(grep -c '^xdotool getactivewindow\$' "\$MOCK_CALLS") + 1 ))
  echo "xdotool \$*" >> "\$MOCK_CALLS"
  case "\$N" in
    1) echo "111" ;;
    2|3|4) echo "222" ;;
    *) echo "444" ;;
  esac
else
  echo "xdotool \$*" >> "\$MOCK_CALLS"
fi
EOF
  mock_bin ohmydebn-gtile-apply <<'EOF'
#!/bin/bash
echo "ohmydebn-gtile-apply $*" >> "$MOCK_CALLS"
EOF
  mock_bin sleep <<'EOF'
#!/bin/bash
exit 0
EOF
  mock_bin fake-app <<'EOF'
#!/bin/bash
exit 0
EOF
  # ohmydebn-launch-tiled-watch-second is a separate script (setsid needs
  # a real executable to launch, not an inline function - see its own
  # comment for why), so it needs its own patched copy with the same
  # xdotool/ohmydebn-gtile-apply/sleep redirects, and ohmydebn-launch-
  # tiled's own reference to it patched to point at that copy.
  sed -e "s#/usr/bin/xdotool#$MOCK_BIN/xdotool#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-apply#$MOCK_BIN/ohmydebn-gtile-apply#g" \
    -e "s#/usr/bin/sleep#$MOCK_BIN/sleep#g" \
    "$WATCH_SECOND_SCRIPT" >"$MOCK_DIR/launch-tiled-watch-second-patched.sh"
  chmod +x "$MOCK_DIR/launch-tiled-watch-second-patched.sh"
  sed -e "s#/usr/bin/xdotool#$MOCK_BIN/xdotool#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-gtile-apply#$MOCK_BIN/ohmydebn-gtile-apply#g" \
    -e "s#/usr/bin/sleep#$MOCK_BIN/sleep#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-launch-tiled-watch-second#$MOCK_DIR/launch-tiled-watch-second-patched.sh#g" \
    "$SCRIPT" >"$MOCK_DIR/launch-tiled-patched.sh"
}

# Waits (real, short sleeps - the mocked sleep above is only for the
# script under test's own internal polling) for the detached background
# watcher to catch up, rather than a single fixed delay that could be
# flaky under load.
wait_for_gtile_call() {
  local needle="$1"
  for _ in $(seq 1 50); do
    grep -q "$needle" "$MOCK_CALLS" 2>/dev/null && return 0
    command sleep 0.05
  done
  return 1
}

# Scenario 5: OHMYDEBN_LAUNCH_TILED_WATCH_SECOND=1 - the cliamp/socrates/
# claude-code/ai-tiled case this exists for. The first window (222, e.g.
# an install-presentation terminal) is tiled immediately as before, and
# once a genuinely different second window (444, the real app) appears,
# the detached background watcher tiles that one too.
mock_init
setup_mocks_second_window
OHMYDEBN_LAUNCH_TILED_WATCH_SECOND=1 PATH="$(mock_path)" \
  bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 1 1 1 1 -- fake-app >/dev/null 2>&1
assert_contains "WATCH_SECOND=1: first window (222) tiled immediately" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 222 2 2 1 1 1 1"
wait_for_gtile_call "ohmydebn-gtile-apply 444 "
assert_contains "WATCH_SECOND=1: second window (444) tiled once it appears" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 444 2 2 1 1 1 1"
mock_cleanup

# Scenario 6: same window sequence, but WATCH_SECOND unset (every caller
# except cliamp/socrates/claude-code/ai-tiled) - only the first window
# ever gets tiled; 444 must never be, since no caller other than those
# four expects (or wants) a second install-then-launch window to exist.
mock_init
setup_mocks_second_window
PATH="$(mock_path)" bash "$MOCK_DIR/launch-tiled-patched.sh" 2 2 1 1 1 1 -- fake-app >/dev/null 2>&1
command sleep 0.3 # grace period - confirms absence, not just "hasn't happened yet"
assert_contains "WATCH_SECOND unset: first window (222) still tiled" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 222 2 2 1 1 1 1"
assert_not_contains "WATCH_SECOND unset: second window (444) never tiled" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-gtile-apply 444 "
mock_cleanup

test_summary
