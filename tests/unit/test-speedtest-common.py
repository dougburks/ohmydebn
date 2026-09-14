#!/usr/bin/python3
#
# Pure-logic regression tests for bin/ohmydebn_speedtest_common.py, shared
# by ohmydebn-network-speedtest-gui and ohmydebn-disk-speedtest-gui: dial
# auto-scaling, the digital-readout number format, and the theme-palette
# derivation. Deliberately excludes anything that needs a real X
# display (SpeedDial's Cairo drawing) - importing the module itself is
# safe with no DISPLAY set, the same way test-python-pickers.py's own
# header comment already established for ohmydebn-menu-picker: gi/Gtk/Gdk
# import fine without one, only a call that actually touches
# Gdk.Display.get_default() would crash.

import os
import sys
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BIN = os.path.join(REPO_ROOT, "bin")

TESTS_RUN = 0
TESTS_FAILED = 0


def check(desc, condition):
    global TESTS_RUN, TESTS_FAILED
    TESTS_RUN += 1
    if condition:
        print(f"  ok - {desc}")
    else:
        print(f"  FAIL - {desc}")
        TESTS_FAILED += 1


def check_eq(desc, actual, expected):
    global TESTS_RUN, TESTS_FAILED
    TESTS_RUN += 1
    if actual == expected:
        print(f"  ok - {desc}")
    else:
        print(f"  FAIL - {desc}")
        print(f"    expected: {expected!r}")
        print(f"    actual:   {actual!r}")
        TESTS_FAILED += 1


def load(name):
    return SourceFileLoader(name, os.path.join(BIN, name)).load_module()


print("=== ohmydebn_speedtest_common (pure logic) ===")
st = load("ohmydebn_speedtest_common.py")

# expand_scale(): the dial's full-scale latch. A reading past 92% of the
# current scale jumps to the smallest later stop that comfortably fits it
# (never exactly the incoming value's own bracket - Omarchy's own comment
# on the QML equivalent: "the needle/arc never quite pins at full
# deflection"), and the scale itself only ever grows, never shrinks, even
# for a reading that would fit a smaller stop than the one already
# latched.
check_eq("expand_scale: comfortably inside the base stop stays there", st.expand_scale(100, 50), 100)
check_eq(
    "expand_scale: past 92% of the current stop jumps to the next one up, not just past it",
    st.expand_scale(100, 95),
    250,
)
check_eq(
    "expand_scale: never shrinks back down for a small reading once latched higher",
    st.expand_scale(1000, 10),
    1000,
)
check_eq(
    "expand_scale: a reading past every real stop latches the largest one, not an unbounded scale",
    st.expand_scale(100, 50000),
    st.SCALE_STOPS[-1],
)
check_eq(
    "expand_scale: exactly 92% of a stop still counts as fitting (boundary is <=, not <)",
    st.expand_scale(100, 100 * 0.92),
    100,
)

# format_reading(): the center digital readout. Sub-10 values keep one
# decimal place (a whole-number rounding there would make anything under
# 1 Mbps/MB/s read as a flat, uninformative "0"); 10 and up round to a
# thousands-grouped integer instead, matching how each terminal version's
# own format_mbps() draws this same line.
check_eq("format_reading: near-zero keeps one decimal", st.format_reading(0.0), "0.0")
check_eq("format_reading: sub-10 keeps one decimal", st.format_reading(3.2), "3.2")
check_eq("format_reading: just under 10 still uses the decimal format", st.format_reading(9.9), "9.9")
check_eq("format_reading: 10 and up drops to a grouped integer", st.format_reading(10.0), "10")
check_eq("format_reading: thousands get a grouping comma", st.format_reading(1234.4), "1,234")
check_eq("format_reading: rounds to the nearest integer, not truncates", st.format_reading(1234.6), "1,235")

# Palette wiring: reading/parsing picker-colors now lives in the shared
# ohmydebn_theme_colors module (covered by its own tests in
# test-theme-colors.py - the old load_accent_color() here is gone). What's
# left to pin down here is the derivation: every foreground-role color
# shares fg0's RGB with only the alpha varying (the original Omarchy
# overlay's tick/text hierarchy), the accent is a bare RGB triple the
# Cairo code can splat with its own alphas, and the error red stays
# fixed and theme-independent.
check_eq("palette: track shares the foreground RGB", st.COLOR_TRACK[:3], st.COLOR_TEXT[:3])
check_eq("palette: minor ticks share the foreground RGB", st.COLOR_TICK_MINOR[:3], st.COLOR_TEXT[:3])
check_eq("palette: major ticks share the foreground RGB", st.COLOR_TICK_MAJOR[:3], st.COLOR_TEXT[:3])
check("palette: dim text is dimmer than full text", st.COLOR_TEXT_DIM[3] < st.COLOR_TEXT[3])
check_eq("palette: error red is fixed, not theme-derived", st.COLOR_ERROR, (1, 0.42, 0.42, 1))
check(
    "palette: accent is an RGB triple of 0-1 floats",
    len(st.COLOR_ACCENT) == 3 and all(0 <= c <= 1 for c in st.COLOR_ACCENT),
)

# SpeedDial(): a bare construction (no draw, no display needed) still
# needs a real label/unit and starting state - regression guard for the
# constructor signature itself, since both GUIs pass (label, unit)
# positionally and a silent argument-order swap wouldn't otherwise be
# caught by anything display-free.
dial = st.SpeedDial("READ", "MB/s")
check_eq("SpeedDial: label is stored as given", dial.label, "READ")
check_eq("SpeedDial: unit is stored as given", dial.unit, "MB/s")
check_eq("SpeedDial: starts at the base scale stop", dial.full_scale, st.SCALE_STOPS[0])
check("SpeedDial: starts idle (not live)", dial.live is False)
dial.set_value(42.0)
check("SpeedDial: set_value() marks it live", dial.live is True)
check_eq("SpeedDial: set_value() records the value", dial.value, 42.0)
dial.stop()
check("SpeedDial: stop() clears live without touching the value", dial.live is False)
check_eq("SpeedDial: stop() leaves the last value in place", dial.value, 42.0)
dial.reset()
check_eq("SpeedDial: reset() zeroes the value", dial.value, 0.0)
check_eq("SpeedDial: reset() zeroes the shown (eased) value too", dial.shown, 0.0)
check_eq("SpeedDial: reset() drops the scale back to the base stop", dial.full_scale, st.SCALE_STOPS[0])

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(0 if TESTS_FAILED == 0 else 1)
