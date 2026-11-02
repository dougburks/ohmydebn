#!/usr/bin/python3
#
# Pure-logic tests for bin/ohmydebn-console, run by test-console.sh: which
# way a key press goes (launch, hide or show) and where the window goes.
# Importing the script is safe with no DISPLAY: Gtk, Gdk and Wnck are only
# imported inside main().

import os
import sys
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

TESTS_RUN = 0
TESTS_FAILED = 0


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


print("=== bin/ohmydebn-console (pure logic) ===")
console = SourceFileLoader("ohmydebn_console", os.path.join(REPO_ROOT, "bin", "ohmydebn-console")).load_module()

check_eq("no console: launch one", console.decide(False, False), "launch")
check_eq("the console is the active window: hide it", console.decide(True, True), "hide")
check_eq("the console exists but isn't active (minimized, behind, elsewhere): show it",
         console.decide(True, False), "show")

# 70% by 60%, centered in the work area (the monitor without the panel).
check_eq("centered in a work area below a 40px top panel",
         console.placement((0, 40, 2540, 1274)), (381, 295, 1778, 764))
check_eq("centered on a second monitor to the right",
         console.placement((1920, 0, 1920, 1080)), (1920 + 288, 216, 1344, 648))
check_eq("odd sizes round down and stay inside the area",
         console.placement((0, 0, 1001, 701)), (150, 140, 700, 420))

check_eq("its window class is the one gTile leaves floating", console.WM_CLASS, "OhMyDebnConsole")
check_eq("it runs ohmydebn-console-run", console.RUN, "/usr/share/ohmydebn/bin/ohmydebn-console-run")

print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
