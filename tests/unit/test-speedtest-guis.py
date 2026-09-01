#!/usr/bin/python3
#
# Pure-logic regression tests for the parts of ohmydebn-network-speedtest-gui
# that don't need a real network interface or X display - currently just
# friendly_connection_name(), which turns the interface name detected by
# detect_iface() into the title-bar label Omarchy's own speed-test panel
# shows (e.g. "ETHERNET", "Wi-Fi"). Importing the script itself is safe
# with no DISPLAY set, same reasoning as test-speedtest-common.py's own
# header comment: gi/Gtk/Gdk import fine, nothing here touches a real
# display since main() is guarded behind __name__ == "__main__".

import os
import sys
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BIN = os.path.join(REPO_ROOT, "bin")

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


def load(name):
    return SourceFileLoader(name, os.path.join(BIN, name)).load_module()


print("=== ohmydebn-network-speedtest-gui (pure logic) ===")
net = load("ohmydebn-network-speedtest-gui")

check_eq("friendly_connection_name: wlan-style names read as Wi-Fi", net.friendly_connection_name("wlan0"), "Wi-Fi")
check_eq("friendly_connection_name: wwan-style names also read as Wi-Fi", net.friendly_connection_name("wwan0"), "Wi-Fi")
check_eq("friendly_connection_name: enp-style names read as Ethernet", net.friendly_connection_name("enp3s0"), "Ethernet")
check_eq("friendly_connection_name: eth-style names read as Ethernet", net.friendly_connection_name("eth0"), "Ethernet")
check_eq(
    "friendly_connection_name: anything unrecognized falls back to the raw name, uppercased",
    net.friendly_connection_name("tailscale0"),
    "TAILSCALE0",
)

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(0 if TESTS_FAILED == 0 else 1)
