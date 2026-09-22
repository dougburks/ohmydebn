#!/bin/bash
#
# Unit tests for bin/ohmydebn-doctor-tiling's pure pieces - the region
# classifier the live assertions rest on, the mode-cycle arithmetic, the
# overlap test - plus the parts of its live flow that can be checked
# without a desktop: it skips cleanly (exit 0, a skip line) when there's
# no Cinnamon session, and ohmydebn-doctor's --exercise-tiling flag
# actually invokes it. The six-window sequences themselves can only run in
# a real session (the per-distro VMs).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-doctor-tiling"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-doctor-tiling ==="

# Load the functions only.
# shellcheck disable=SC1090
OHMYDEBN_DOCTOR_TILING_LIB=1 source "$SCRIPT"

# --- classify_region on a 2540x1314 screen with a ~110px top panel and 10px gaps (real numbers from a live session) ---
SW=2540; SH=1314
assert_eq "classify: left half with panel and gaps" "left-half" "$(classify_region 20 130 1255 1218 $SW $SH)"
assert_eq "classify: right half" "right-half" "$(classify_region 1285 130 1255 1218 $SW $SH)"
assert_eq "classify: full (maximized with gaps)" "full" "$(classify_region 10 120 2520 1184 $SW $SH)"
assert_eq "classify: top-right quarter" "top-right" "$(classify_region 1285 130 1245 599 $SW $SH)"
assert_eq "classify: bottom-right quarter" "bottom-right" "$(classify_region 1285 739 1245 599 $SW $SH)"
assert_eq "classify: top-left quarter" "top-left" "$(classify_region 20 130 1245 599 $SW $SH)"
assert_eq "classify: bottom-left quarter" "bottom-left" "$(classify_region 20 739 1245 599 $SW $SH)"
assert_eq "classify: top half" "top-half" "$(classify_region 10 120 2520 590 $SW $SH)"
assert_eq "classify: bottom half" "bottom-half" "$(classify_region 10 720 2520 590 $SW $SH)"
assert_eq "classify: a quarter-width column (unlimited mode's 4th split) is 'other'" "other" "$(classify_region 1900 130 620 1218 $SW $SH)"
assert_eq "classify: a small floating window is 'other'" "other" "$(classify_region 800 400 500 300 $SW $SH)"
# The exact 'stuck' shape from the reported bug: window 2 left top-right after window 3 closed.
assert_eq "classify: the bug's stuck window reads as top-right, not right-half" "top-right" "$(classify_region 1285 130 1245 599 $SW $SH)"
# Boundary tolerance: 45% wide still counts as a half.
assert_eq "classify: 45%-wide tall window still reads as a half" "left-half" "$(classify_region 0 0 1143 1314 $SW $SH)"

# --- mode_cycle_steps follows the extension's cycle order and wraps ---
assert_eq "cycle: off -> rules is 1 step" "1" "$(mode_cycle_steps off rules)"
assert_eq "cycle: off -> scrollable is 4 steps" "4" "$(mode_cycle_steps off scrollable)"
assert_eq "cycle: scrollable -> off wraps to 1 step" "1" "$(mode_cycle_steps scrollable off)"
assert_eq "cycle: traditional-full -> traditional wraps around (4 steps)" "4" "$(mode_cycle_steps traditional-full traditional)"
assert_eq "cycle: same mode is 0 steps" "0" "$(mode_cycle_steps rules rules)"
assert_eq "cycle: unknown mode is -1" "-1" "$(mode_cycle_steps off bogus)"

# --- overlaps ---
if overlaps 0 0 100 100 50 50 100 100; then assert_eq "overlaps: intersecting rectangles" "yes" "yes"; else assert_eq "overlaps: intersecting rectangles" "yes" "no"; fi
if overlaps 0 0 100 100 100 0 100 100; then assert_eq "overlaps: edge-adjacent rectangles do not overlap" "no" "yes"; else assert_eq "overlaps: edge-adjacent rectangles do not overlap" "no" "no"; fi
if overlaps 0 0 100 100 500 500 10 10; then assert_eq "overlaps: distant rectangles" "no" "yes"; else assert_eq "overlaps: distant rectangles" "no" "no"; fi

# --- no Cinnamon session: skips cleanly ---
OUT=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" bash "$SCRIPT" 2>&1); STATUS=$?
assert_eq "no session: exits 0" "0" "$STATUS"
assert_contains "no session: says why it skipped" "$OUT" "skip - tiling exercise (needs a Cinnamon session with a display)"
assert_contains "no session: prints its summary" "$OUT" "0 ok, 0 failed, 1 skipped"

# --- doctor wiring: --exercise-tiling runs the script; unknown flags are rejected ---
mock_init
ROOT="$MOCK_DIR/root"; OMD="$ROOT/usr/share/ohmydebn"; H="$MOCK_DIR/home"
mkdir -p "$OMD/bin" "$H"
# env -i below strips the exported mock_log helper, so this stub logs
# straight to the calls file, whose path is passed through explicitly.
printf '#!/bin/bash\necho "ohmydebn-doctor-tiling" >>"$MOCK_CALLS"\nexit 3\n' >"$OMD/bin/ohmydebn-doctor-tiling"; chmod +x "$OMD/bin/ohmydebn-doctor-tiling"
for c in dpkg dpkg-query apt-cache update-alternatives systemctl gsettings python3; do mock_bin "$c" <<'EOF2'
#!/bin/bash
exit 1
EOF2
done
env -i HOME="$H" PATH="$MOCK_BIN:/usr/bin:/bin" MOCK_CALLS="$MOCK_CALLS" OHMYDEBN_DOCTOR_SYSROOT="$ROOT" /bin/bash "$REPO_ROOT/bin/ohmydebn-doctor" --exercise-tiling >/dev/null 2>&1; STATUS=$?
assert_contains "doctor --exercise-tiling: runs ohmydebn-doctor-tiling" "$(cat "$MOCK_CALLS")" "ohmydebn-doctor-tiling"
assert_eq "doctor --exercise-tiling: a failing exercise makes the doctor exit non-zero" "1" "$STATUS"
: >"$MOCK_CALLS"
env -i HOME="$H" PATH="$MOCK_BIN:/usr/bin:/bin" MOCK_CALLS="$MOCK_CALLS" OHMYDEBN_DOCTOR_SYSROOT="$ROOT" /bin/bash "$REPO_ROOT/bin/ohmydebn-doctor" >/dev/null 2>&1
assert_eq "doctor without the flag: exercise not run" "" "$(cat "$MOCK_CALLS")"
OUT=$(env -i HOME="$H" PATH="$MOCK_BIN:/usr/bin:/bin" /bin/bash "$REPO_ROOT/bin/ohmydebn-doctor" --bogus 2>&1); STATUS=$?
assert_eq "doctor --bogus: exits 2" "2" "$STATUS"
assert_contains "doctor --bogus: prints usage" "$OUT" "Usage: ohmydebn-doctor [--exercise-tiling]"
mock_cleanup

test_summary
