#!/usr/bin/python3
#
# Pure-logic regression tests for bin/ohmydebn_theme_colors.py, the
# shared picker-colors palette reader used by ohmydebn-update-gui and
# ohmydebn_speedtest_common.py (ohmydebn-menu-picker keeps its own older
# reader - see the module's header). These tests started life inside
# test-update-gui.py when the loader lived in that script, and moved
# here with the code. No display needed - the module is plain Python
# with no gi imports at all.

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


print("=== ohmydebn_theme_colors (pure logic) ===")
tc = SourceFileLoader("ohmydebn_theme_colors", os.path.join(BIN, "ohmydebn_theme_colors.py")).load_module()

# parse_hex_color: the two shapes picker-colors carries, plus graceful
# refusal of anything else (a refused value keeps the default color).
check_eq("parse_hex_color: #RRGGBB", tc.parse_hex_color("#112233"), (0x11 / 255, 0x22 / 255, 0x33 / 255, 1.0))
check_eq(
    "parse_hex_color: #RRGGBBAA carries its alpha",
    tc.parse_hex_color("#509475F2"),
    (0x50 / 255, 0x94 / 255, 0x75 / 255, 0xF2 / 255),
)
check_eq("parse_hex_color: junk is None, not a crash", tc.parse_hex_color("not-a-color"), None)
check_eq("parse_hex_color: wrong length is None", tc.parse_hex_color("#1234"), None)

# css_rgba: alpha override for the dimmed foreground variants.
check_eq("css_rgba: full alpha", tc.css_rgba((1.0, 0.0, 0.0, 1.0)), "rgba(255, 0, 0, 1.000)")
check_eq("css_rgba: alpha override wins", tc.css_rgba((1.0, 1.0, 1.0, 1.0), 0.45), "rgba(255, 255, 255, 0.450)")

# contrast_ratio: picks the readable text color for the accent-filled
# primary button. Pinned against the live bug: Tokyo Night's light-blue
# accent (#7aa2f7) must choose the dark bg1 (#1a1b26) over the light fg0
# (#a9b1d6), and a dark-accent theme must choose fg0 - no fixed pick
# works across themes.
tokyo = {k: tc.parse_hex_color(v) for k, v in {"bg1": "#1a1b26", "bg3": "#7aa2f7", "fg0": "#a9b1d6"}.items()}
check(
    "contrast_ratio: Tokyo Night's light accent picks dark bg1 for button text",
    tc.contrast_ratio(tokyo["bg1"], tokyo["bg3"]) > tc.contrast_ratio(tokyo["fg0"], tokyo["bg3"]),
)
dark_accent = {k: tc.parse_hex_color(v) for k, v in {"bg1": "#101010", "bg3": "#303060", "fg0": "#e0e0e0"}.items()}
check(
    "contrast_ratio: a dark accent picks light fg0 for button text",
    tc.contrast_ratio(dark_accent["fg0"], dark_accent["bg3"]) > tc.contrast_ratio(dark_accent["bg1"], dark_accent["bg3"]),
)
check_eq("contrast_ratio: identical colors are ratio 1", tc.contrast_ratio(tokyo["bg1"], tokyo["bg1"]), 1.0)
check(
    "contrast_ratio: black vs white is the maximum 21",
    abs(tc.contrast_ratio((0, 0, 0, 1), (1, 1, 1, 1)) - 21.0) < 0.01,
)

# load_theme_colors: overlays the theme file over the picker's defaults,
# key by key - a malformed value or missing key keeps its default.
with tempfile.TemporaryDirectory() as tmp:
    theme_file = os.path.join(tmp, "picker-colors")
    with open(theme_file, "w", encoding="utf-8") as f:
        f.write("bg1=#111c18\nbg3=zzz-not-hex\nnot_a_key=#ffffff\n")
    colors = tc.load_theme_colors(theme_file)
    check_eq("load_theme_colors: file value wins", colors["bg1"], tc.parse_hex_color("#111c18"))
    check_eq(
        "load_theme_colors: malformed value keeps the default",
        colors["bg3"],
        tc.parse_hex_color(tc.DEFAULT_THEME_COLORS["bg3"]),
    )
    check("load_theme_colors: unknown keys ignored", "not_a_key" not in colors)
    missing = tc.load_theme_colors(os.path.join(tmp, "nope"))
    check_eq(
        "load_theme_colors: missing file is all defaults",
        missing,
        {k: tc.parse_hex_color(v) for k, v in tc.DEFAULT_THEME_COLORS.items()},
    )

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
