#!/usr/bin/python3
#
# Pure-logic regression tests for bin/ohmydebn_speedtest_common.py, shared
# by ohmydebn-network-speedtest-gui and ohmydebn-disk-speedtest-gui: dial
# auto-scaling, the digital-readout number format, and the theme-accent
# color loader. Deliberately excludes anything that needs a real X
# display (SpeedDial's Cairo drawing) - importing the module itself is
# safe with no DISPLAY set, the same way test-python-pickers.py's own
# header comment already established for ohmydebn-menu-picker: gi/Gtk/Gdk
# import fine without one, only a call that actually touches
# Gdk.Display.get_default() would crash.

import os
import sys
import tempfile
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

# load_accent_color(): reads ~/.config/ohmydebn/current/picker-colors'
# "bg3" field, the same accent/border color ohmydebn-menu-picker's own
# load_theme_colors() reads from the same file - redirects HOME for the
# duration of the test rather than monkeypatching a path constant, the
# same technique test-python-pickers.py uses for that same file.
old_home = os.environ.get("HOME")
fake_home = tempfile.mkdtemp(prefix="ohmydebn-test-home-")
try:
    os.environ["HOME"] = fake_home
    colors_dir = os.path.join(fake_home, ".config", "ohmydebn", "current")
    os.makedirs(colors_dir)
    picker_colors_path = os.path.join(colors_dir, "picker-colors")

    with open(picker_colors_path, "w", encoding="utf-8") as f:
        f.write("bg0=#2e3440F2\nbg1=#2e3440\nbg3=#81a1c1F2\nfg0=#d8dee9\n")
    check_eq(
        "load_accent_color: parses bg3's hex into a 0-1 float RGB tuple, ignoring the alpha suffix",
        st.load_accent_color(),
        (0x81 / 255, 0xA1 / 255, 0xC1 / 255),
    )

    with open(picker_colors_path, "w", encoding="utf-8") as f:
        f.write("bg0=#2e3440\nfg0=#d8dee9\n")
    check_eq(
        "load_accent_color: falls back to the default blue when bg3 is missing from the file",
        st.load_accent_color(),
        (0.40, 0.69, 1.0),
    )

    os.remove(picker_colors_path)
    check_eq(
        "load_accent_color: falls back to the default blue when the file doesn't exist at all",
        st.load_accent_color(),
        (0.40, 0.69, 1.0),
    )
finally:
    if old_home is None:
        del os.environ["HOME"]
    else:
        os.environ["HOME"] = old_home

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
