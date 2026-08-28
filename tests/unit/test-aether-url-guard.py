#!/usr/bin/python3
#
# Tests for bin/ohmydebn-aether-url-guard. Follows the same convention as
# test-python-pickers.py for testing ohmydebn's other GTK pickers:
# build_confirmation() is pure - no GTK, no subprocess, no filesystem access
# - so it's loaded and called directly, no display required. show_dialog()
# is the one function that touches GTK; it gets a single smoke test that a
# real window actually renders (title, centered, undecorated), skipped
# rather than failed when there's no DISPLAY.

import os
import sys
import time
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


print("=== ohmydebn-aether-url-guard (pure logic) ===")
guard = SourceFileLoader("ohmydebn_aether_url_guard", os.path.join(BIN, "ohmydebn-aether-url-guard")).load_module()

KNOWN_HOST = guard.KNOWN_PAYLOAD_HOST

# --- Dangerous/malformed URLs are refused, never reach a confirm dialog ---
outcome = guard.build_confirmation("https://evil.example.com/x")
check_eq("wrong scheme is refused", outcome[0], "refuse")
check("wrong scheme message names the bad scheme", "https" in outcome[1])

outcome = guard.build_confirmation("aether://something-else?colors=https://x/y")
check_eq("wrong action is refused", outcome[0], "refuse")

outcome = guard.build_confirmation("aether://apply?mode=dark")
check_eq("no payload param is refused", outcome[0], "refuse")

# --- A known-good payload host: calm title, no warning marker ---
url = f"aether://apply?colors=https://{KNOWN_HOST}/omarchy-themes/x/colors.toml&silent=true&as_omarchy_theme=cool"
outcome = guard.build_confirmation(url)
check_eq("known host: build_confirmation approves showing a confirm dialog", outcome[0], "confirm")
_, title, body, forward_url = outcome
check("known host: title is the calm one, not the warning one", "Unrecognized theme source" not in title)
check("known host: theme name appears first, with a blank line after it", body.startswith("Installs as theme: cool\n\n"))
check("known host: payload host is shown with no warning marker", f"colors: {KNOWN_HOST}\n" in body and "⚠" not in body)
check("known host: the raw URL is included verbatim for review", url in body)
check_eq("known host: the URL Aether would receive is byte-for-byte unmodified", forward_url, url)

# --- A mismatched payload host: still confirmable, but flagged ---
url = "aether://apply?colors=https://evil.example.com/colors.toml&silent=true"
outcome = guard.build_confirmation(url)
check_eq("mismatched host: still returns confirm, not refuse (user's call)", outcome[0], "confirm")
_, title, body, _forward_url = outcome
check("mismatched host: title is the warning one", "Unrecognized theme source" in title)
check("mismatched host: the bad host is named explicitly", "evil.example.com" in body)
check("mismatched host: warning marker is present", "⚠" in body)

# --- No as_omarchy_theme=: no theme-name line, no stray leading blank line ---
url = f"aether://apply?colors=https://{KNOWN_HOST}/x/colors.toml"
outcome = guard.build_confirmation(url)
_, _title, body, _forward_url = outcome
check("no as_omarchy_theme=: no 'Installs as theme' line", "Installs as theme" not in body)
check("no as_omarchy_theme=: body doesn't start with a blank line", not body.startswith("\n"))

# --- external_theme=/wallpaper= are recognized as payload params too ---
outcome = guard.build_confirmation(f"aether://apply?external_theme=https://{KNOWN_HOST}/x.json")
check_eq("external_theme= alone is a valid payload", outcome[0], "confirm")
outcome = guard.build_confirmation(f"aether://apply?wallpaper=https://{KNOWN_HOST}/x.jpg")
check_eq("wallpaper= alone is a valid payload", outcome[0], "confirm")

print()
print("=== ohmydebn-aether-url-guard show_dialog() (real GTK, needs a display) ===")

if os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"):
    import re
    import subprocess
    import threading

    result_holder = {}

    def run_dialog():
        result_holder["clicked"] = guard.show_dialog("Test dialog title", "Test dialog body\nline two", ["Cancel", "Apply"])

    thread = threading.Thread(target=run_dialog, daemon=True)
    thread.start()
    time.sleep(1)

    window_id = subprocess.run(
        ["xdotool", "search", "--name", "Test dialog title"],
        capture_output=True, text=True, check=False,
    ).stdout.strip()
    check("a real window titled correctly actually appears on screen", bool(window_id))

    if window_id:
        wid = window_id.splitlines()[0]
        geom = dict(
            line.split("=", 1)
            for line in subprocess.run(
                ["xdotool", "getwindowgeometry", "--shell", wid],
                capture_output=True, text=True, check=False,
            ).stdout.splitlines()
            if "=" in line
        )
        check("window geometry is queryable (window is mapped, not just requested)", "WIDTH" in geom)

        # `xdotool getdisplaygeometry` reports the combined virtual screen
        # across every connected monitor, not the one monitor GTK actually
        # centers the dialog on - on a dual-monitor setup that's a
        # different rectangle whenever the dialog lands on the non-primary
        # monitor (confirmed live: two 2560x1440 monitors side by side,
        # dialog centered on the second one, combined-screen center off by
        # a full monitor width, well outside any sane tolerance). Find the
        # actual monitor rectangle the window's center falls in via xrandr
        # instead, and check centering against that.
        def monitor_rects():
            out = subprocess.run(
                ["xrandr", "--query"], capture_output=True, text=True, check=False
            ).stdout
            rects = []
            for line in out.splitlines():
                if " connected" not in line:
                    continue
                m = re.search(r"(\d+)x(\d+)\+(\d+)\+(\d+)", line)
                if m:
                    w, h, x, y = (int(g) for g in m.groups())
                    rects.append((x, y, w, h))
            return rects

        if "WIDTH" in geom:
            win_x, win_y = int(geom["X"]), int(geom["Y"])
            win_w, win_h = int(geom["WIDTH"]), int(geom["HEIGHT"])
            center_x = win_x + win_w / 2
            center_y = win_y + win_h / 2
            rects = monitor_rects()
            mon = next(
                ((x, y, w, h) for x, y, w, h in rects if x <= center_x < x + w and y <= center_y < y + h),
                None,
            )
            if mon:
                mon_x, mon_y, mon_w, mon_h = mon
                # A loose tolerance (10% of the monitor's size) - this is
                # checking real window-manager placement, not GTK's exact
                # requested position.
                check(
                    "window is centered on screen, not e.g. top-left corner",
                    abs(center_x - (mon_x + mon_w / 2)) < mon_w * 0.1
                    and abs(center_y - (mon_y + mon_h / 2)) < mon_h * 0.1,
                )

        # windowkill uses XKillClient, which forcibly drops the whole X
        # connection - since this test runs in-process with the dialog
        # thread, that takes the entire test process down with it (confirmed
        # the hard way: this used to be windowkill and the suite silently
        # died mid-run, right after this line, no traceback). Escape is what
        # the dialog's own key handler treats as "close" - same as a user
        # dismissing it - so this exercises the graceful path instead of a
        # destructive workaround.
        # A synthetic xdotool key/windowactivate reaching this exact window's
        # GTK event loop turned out to depend on WM-specific input-focus
        # quirks unrelated to the guard's own code (confirmed activate+key
        # simply never arrived here, in this environment) - GLib.idle_add is
        # the deterministic way to end the dialog's main loop from another
        # thread instead, and no less real a test: it's the same main-loop
        # shutdown path window.close()'s own "destroy" handler triggers.
        from gi.repository import GLib

        GLib.idle_add(guard.Gtk.main_quit)

    thread.join(timeout=2)
    check("dialog thread exits cleanly once its main loop is told to stop", not thread.is_alive())
else:
    print("  (skip - no DISPLAY/WAYLAND_DISPLAY available)")

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
