#!/usr/bin/python3
#
# Tests for the window switcher (Ctrl+Alt+Tab): bin/ohmydebn_windows.py and
# the parts of ohmydebn-menu-picker --windows that use it. The switcher
# listed windows through libwnck, which only sees X11 windows: in
# Cinnamon's Wayland session it found no screen, crashed, and showed
# nothing. It now asks gTile@OhMyDebn (ListWindows, ActivateWindow), which
# runs inside Cinnamon and sees every window. D-Bus calls go through a
# stand-in, and nothing here needs a display.

import os
import signal
import subprocess
import sys
import tempfile
import time
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BIN = os.path.join(REPO_ROOT, "bin")
sys.path.insert(0, BIN)

import ohmydebn_windows as wl  # noqa: E402
from gi.repository import GLib  # noqa: E402

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
    check(desc, actual == expected)
    if actual != expected:
        print(f"      expected: {expected!r}\n      actual:   {actual!r}")


print("=== bin/ohmydebn_windows.py ===")

calls = []


def fake_call(reply):
    def call(method, params, reply_type):
        calls.append((method, params, reply_type))
        if isinstance(reply, Exception):
            raise reply
        return reply
    return call


# A Wayland session as gTile lists it: Nemo and Brave (Wayland) and
# Alacritty (XWayland) alike, most recently used first.
calls.clear()
windows = wl.list_windows(fake_call(([
    (7, "Home", "Nemo", "nemo.desktop", "org.gnome.Nautilus"),
    (3, "OhMyDebn - Brave", "brave-browser", "brave-browser.desktop", "brave-browser"),
    (9, "doug@vm: ~", "Alacritty", "Alacritty.desktop", "Alacritty"),
],)))
check_eq("list: asks gTile's ListWindows for a(tssss) rows", calls, [("ListWindows", None, "(a(tssss))")])
check_eq("list: every window, in gTile's order", [w.id for w in windows], [7, 3, 9])
check_eq("list: rows become SwitcherWindows", windows[0],
         wl.SwitcherWindow(7, "Home", "Nemo", "nemo.desktop", "org.gnome.Nautilus"))
check_eq("list: no windows is an empty list, not a failure", wl.list_windows(fake_call(([],))), [])
check_eq("list: gTile not answering (old gTile, disabled, absent) is None",
         wl.list_windows(fake_call(GLib.Error("org.freedesktop.DBus.Error.UnknownMethod"))), None)
check_eq("list: a reply of the wrong shape is None", wl.list_windows(fake_call(())), None)
check_eq("list: a malformed row is skipped",
         [w.id for w in wl.list_windows(fake_call(([(1, "a", "b", "c", "d"), (2, "short")],)))], [1])

calls.clear()
check_eq("activate: True when gTile did it", wl.activate_window(7, fake_call(())), True)
check_eq("activate: asks ActivateWindow with the id as a uint64",
         [(m, p.unpack() if p is not None else None, r) for m, p, r in calls], [("ActivateWindow", (7,), None)])
check_eq("activate: the type is (t)", calls[0][1].get_type_string(), "(t)")
check_eq("activate: False when gTile couldn't (window gone)",
         wl.activate_window(7, fake_call(GLib.Error("No such window"))), False)

# Window placement, workspaces and the screen, for scripts (gTile
# 3.0.1-20261113.1's ListWindowGeometry, GetScreen, ActivateWorkspace).
calls.clear()
geometry = wl.list_geometry(fake_call(([
    (4, "ohmydebn-doctor-tiling-1", "Alacritty", "Alacritty.desktop", 2, 10, 40, 950, 1030, False),
    (5, "Home", "Nemo", "nemo.desktop", -1, 0, 0, 800, 600, True),
],)))
check_eq("geometry: asks ListWindowGeometry for a(tsssiiiiib) rows", calls,
         [("ListWindowGeometry", None, "(a(tsssiiiiib))")])
check_eq("geometry: rows become WindowGeometry tuples", geometry[0],
         wl.WindowGeometry(4, "ohmydebn-doctor-tiling-1", "Alacritty", "Alacritty.desktop", 2, 10, 40, 950, 1030, False))
check_eq("geometry: an older gTile without the method is None",
         wl.list_geometry(fake_call(GLib.Error("org.freedesktop.DBus.Error.UnknownMethod"))), None)
check_eq("geometry: a malformed row is skipped",
         [w.id for w in wl.list_geometry(fake_call(([(1, "a", "b", "c", 0, 0, 0, 1, 1, False), (2, "short")],)))], [1])

calls.clear()
check_eq("screen: width, height, workspaces, active", wl.get_screen(fake_call((1920, 1080, 4, 1))), (1920, 1080, 4, 1))
check_eq("screen: asks GetScreen", calls, [("GetScreen", None, "(iiii)")])
check_eq("screen: gTile not answering is None", wl.get_screen(fake_call(GLib.Error("x"))), None)
check_eq("screen: a reply of the wrong shape is None", wl.get_screen(fake_call(())), None)

calls.clear()
check_eq("workspace: True when gTile switched", wl.activate_workspace(2, fake_call(())), True)
check_eq("workspace: asks ActivateWorkspace with an (i)",
         [(m, p.get_type_string(), p.unpack()) for m, p, r in calls], [("ActivateWorkspace", "(i)", (2,))])
check_eq("workspace: False when it couldn't", wl.activate_workspace(9, fake_call(GLib.Error("No such workspace"))), False)

# Finding an app's window: X11 says WM_CLASS "KeePassXC", Wayland app ID
# "org.keepassxc.KeePassXC" - Ctrl+Shift+K found neither through xdotool
# on Wayland.
x11_keepass = wl.SwitcherWindow(11, "Passwords - KeePassXC", "KeePassXC", "", "")
wayland_keepass = wl.SwitcherWindow(12, "Passwords - KeePassXC", "org.keepassxc.KeePassXC",
                                    "org.keepassxc.KeePassXC.desktop", "")
brave = wl.SwitcherWindow(3, "KeePassXC - Brave", "brave-browser", "brave-browser.desktop", "")
check_eq("class: an X11 WM_CLASS, ignoring case", wl.find_by_class([brave, x11_keepass], "keepassxc"), x11_keepass)
check_eq("class: a Wayland app ID ending in .keepassxc", wl.find_by_class([brave, wayland_keepass], "keepassxc"),
         wayland_keepass)
check_eq("class: the most recently used match first", wl.find_by_class([wayland_keepass, x11_keepass], "keepassxc"),
         wayland_keepass)
check_eq("class: a title naming the app isn't a match", wl.find_by_class([brave], "keepassxc"), None)
check_eq("class: a class only containing the name isn't a match",
         wl.find_by_class([wl.SwitcherWindow(1, "t", "keepassxc-proxy", "", "")], "keepassxc"), None)
check_eq("class: no windows (gTile not answering)", wl.find_by_class(None, "keepassxc"), None)

# The command-line tool scripts call, with gTile's answers stood in for.
gw = SourceFileLoader("gtile_windows", os.path.join(BIN, "ohmydebn-gtile-windows")).load_module()
saved_cli = (gw.windows_lib.list_windows, gw.windows_lib.activate_window, gw.windows_lib.list_geometry,
             gw.windows_lib.get_screen, gw.windows_lib.activate_workspace)
activated = []
try:
    gw.windows_lib.list_windows = lambda: [brave, wayland_keepass]
    gw.windows_lib.activate_window = lambda i: activated.append(i) or True
    check_eq("cli activate-class: finds and raises it", (gw.main(["activate-class", "keepassxc"]), activated), (0, [12]))
    activated.clear()
    check_eq("cli activate-class: exit 1 when there's no such window", (gw.main(["activate-class", "gimp"]), activated),
             (1, []))
    gw.windows_lib.list_windows = lambda: None
    check_eq("cli activate-class: exit 1 when gTile doesn't answer", gw.main(["activate-class", "keepassxc"]), 1)
    check_eq("cli activate: by id", (gw.main(["activate", "7"]), activated), (0, [7]))

    import io
    from contextlib import redirect_stdout
    gw.windows_lib.list_geometry = lambda: [
        wl.WindowGeometry(4, "a\ttitle\nwith breaks", "Alacritty", "", 2, 10, 40, 950, 1030, True)]
    out = io.StringIO()
    with redirect_stdout(out):
        status = gw.main(["geometry"])
    check_eq("cli geometry: tab-separated, title last and on one line", (status, out.getvalue()),
             (0, "4\t2\t10\t40\t950\t1030\t1\ta title with breaks\n"))
    gw.windows_lib.list_geometry = lambda: None
    check_eq("cli geometry: exit 1 on an older gTile", gw.main(["geometry"]), 1)

    gw.windows_lib.get_screen = lambda: (1920, 1080, 4, 0)
    out = io.StringIO()
    with redirect_stdout(out):
        status = gw.main(["screen"])
    check_eq("cli screen: one line", (status, out.getvalue()), (0, "1920 1080 4 0\n"))

    gw.windows_lib.activate_workspace = lambda i: i < 4
    check_eq("cli workspace: switches", gw.main(["workspace", "3"]), 0)
    check_eq("cli workspace: exit 1 for one that doesn't exist", gw.main(["workspace", "4"]), 1)

    with redirect_stdout(io.StringIO()):
        import contextlib
        with contextlib.redirect_stderr(io.StringIO()):
            check_eq("cli: no command is a usage error", gw.main([]), 2)
            check_eq("cli: an unknown command is a usage error", gw.main(["frobnicate"]), 2)
            check_eq("cli: activate needs a numeric id", gw.main(["activate", "x"]), 2)
            check_eq("cli: workspace needs an index", gw.main(["workspace"]), 2)
finally:
    (gw.windows_lib.list_windows, gw.windows_lib.activate_window, gw.windows_lib.list_geometry,
     gw.windows_lib.get_screen, gw.windows_lib.activate_workspace) = saved_cli

check_eq("Wayland: WAYLAND_DISPLAY set", wl.is_wayland_session({"WAYLAND_DISPLAY": "wayland-0"}), True)
check_eq("Wayland: XDG_SESSION_TYPE=wayland", wl.is_wayland_session({"XDG_SESSION_TYPE": "wayland"}), True)
check_eq("X11: neither", wl.is_wayland_session({"XDG_SESSION_TYPE": "x11", "DISPLAY": ":0"}), False)
check_eq("X11: an empty WAYLAND_DISPLAY", wl.is_wayland_session({"WAYLAND_DISPLAY": ""}), False)

check_eq("icons: the app's icon first, then names from WM_CLASS and the .desktop file",
         wl.icon_candidates(wl.SwitcherWindow(1, "t", "Brave-browser", "brave-browser.desktop", "brave")),
         ["brave", "brave-browser", "Brave-browser"])
check_eq("icons: no app matched - names from the window only, no repeats",
         wl.icon_candidates(wl.SwitcherWindow(1, "t", "xterm", "", "")), ["xterm"])
check_eq("icons: an icon file path is kept as is",
         wl.icon_candidates(wl.SwitcherWindow(1, "t", "", "", "/opt/app/icon.png")), ["/opt/app/icon.png"])

check_eq("lock: in the runtime directory",
         wl.switcher_lock_path({"XDG_RUNTIME_DIR": "/run/user/1000"}), "/run/user/1000/ohmydebn-window-switcher.lock")
check(
    "lock: else in the user's cache directory",
    wl.switcher_lock_path({}).endswith("/.cache/ohmydebn-window-switcher.lock"))

# One switcher at a time: a second one finds the first.
scratch = tempfile.mkdtemp()
lock = os.path.join(scratch, "switcher.lock")
HOLDER = f"""
import os, signal, sys, time
sys.path.insert(0, {BIN!r})
import ohmydebn_windows as wl
claimed, fd = wl.claim_switcher({lock!r})
got = []
signal.signal(signal.SIGUSR1, lambda *a: got.append(1))
print("claimed" if claimed else "not claimed", flush=True)
deadline = time.time() + 10
while not got and time.time() < deadline:
    time.sleep(0.02)
print("next row" if got else "no signal", flush=True)
"""


def start_holder():
    holder = subprocess.Popen([sys.executable, "-c", HOLDER], stdout=subprocess.PIPE, text=True)
    first = holder.stdout.readline().strip()
    return holder, first


holder, first = start_holder()
check_eq("lock: the first switcher claims it", first, "claimed")
claimed, pid = wl.claim_switcher(lock)
check_eq("lock: a second one doesn't", claimed, False)
check_eq("lock: the second learns the first's PID", pid, holder.pid)
os.kill(holder.pid, signal.SIGUSR1)
check_eq("lock: the first hears from it", holder.stdout.readline().strip(), "next row")
holder.wait()
claimed, fd = wl.claim_switcher(lock)
check_eq("lock: free again once the first has ended", claimed, True)
os.close(fd)
# The fallback, ~/.cache, may not exist yet (no XDG_RUNTIME_DIR, a new
# account): the switcher opened nothing when it didn't.
with tempfile.TemporaryDirectory() as home:
    missing = os.path.join(home, ".cache", "ohmydebn-window-switcher.lock")
    try:
        claimed, fd = wl.claim_switcher(missing)
        os.close(fd)
    except OSError:
        claimed = False
    check_eq("lock: made in a cache directory that doesn't exist yet", claimed, True)

print("=== ohmydebn-menu-picker --windows ===")
mp = SourceFileLoader("ohmydebn_menu_picker_windows", os.path.join(BIN, "ohmydebn-menu-picker")).load_module()

saved = (mp.windows_lib.list_windows, mp.windows_lib.is_wayland_session, mp.windows_lib.activate_window)
mp.windows_lib.list_windows = lambda: []
check_eq("list: gTile's list is used when it answers", mp.load_windows(), [])

mp.windows_lib.list_windows = lambda: None
mp.windows_lib.is_wayland_session = lambda: True
try:
    mp.load_windows()
    raised = False
except mp.SwitcherUnavailable:
    raised = True
check("Wayland without gTile: SwitcherUnavailable, not libwnck's crash", raised)

activated = []
mp.windows_lib.activate_window = lambda wid: activated.append(wid) or True
mp.activate_window(wl.SwitcherWindow(42, "t", "c", "", ""))
check_eq("activate: a gTile-listed window goes back to gTile by id", activated, [42])


# finish(): a SwitcherWindow is a namedtuple, and the app branch takes any
# tuple for an app to launch - windows mode must win.
class FakeSeat:
    def ungrab(self):
        pass


class FakeDisplay:
    @staticmethod
    def get_default():
        return FakeDisplay()

    def get_default_seat(self):
        return FakeSeat()


class FakeGdk:
    Display = FakeDisplay


class FakeGtk:
    @staticmethod
    def main_quit():
        pass


class FakeSelf:
    mode = "windows"
    _closing = False
    on_result = None


launched = []
real = (mp.Gdk, mp.Gtk, mp.launch_app)
mp.Gdk, mp.Gtk, mp.launch_app = FakeGdk, FakeGtk, lambda tokens: launched.append(tokens)
activated.clear()
try:
    mp.Picker.finish(FakeSelf(), wl.SwitcherWindow(5, "t", "c", "app.desktop", ""))
finally:
    mp.Gdk, mp.Gtk, mp.launch_app = real
check_eq("pick: the chosen window is activated", activated, [5])
check_eq("pick: nothing is launched as an app", launched, [])

# A second Ctrl+Alt+Tab while a switcher is open (Wayland: Cinnamon gets
# every tap): it hands the tap to the first and opens no window.
mp.windows_lib.switcher_lock_path = lambda: lock
holder, first = start_holder()
built = []
real_picker = mp.Picker
mp.Picker = lambda **kw: built.append(kw)
try:
    status = mp.run_window_switcher()
finally:
    mp.Picker = real_picker
check_eq("second tap: exits cleanly", status, 0)
check_eq("second tap: opens no second window", built, [])
check_eq("second tap: the open switcher moves to the next row", holder.stdout.readline().strip(), "next row")
holder.wait()

# No way to list windows: said in a notification, not a silent failure.
notified = []
real_run = mp.subprocess.run


def unavailable(**kw):
    raise mp.SwitcherUnavailable()


mp.Picker = unavailable
mp.subprocess.run = lambda args, **kw: notified.append(args)
try:
    status = mp.run_window_switcher()
finally:
    mp.Picker = real_picker
    mp.subprocess.run = real_run
check_eq("unavailable: exits 1", status, 1)
check("unavailable: a notification says why, and points to Alt+Tab",
      len(notified) == 1 and notified[0][0] == "notify-send" and "Alt+Tab" in notified[0][-1])
check_eq("unavailable: the lock is free for the next try", wl.claim_switcher(lock)[0], True)

# The keyboard grab: on X11 it keeps further Tab taps from Cinnamon. On
# Wayland it can't, and trying took the window's focus away as it
# appeared, so on_focus_out closed the switcher before it was seen (Linux
# Mint 27).
grabs = []


class GrabSeat:
    def grab(self, *args):
        grabs.append(args)


class GrabDisplay:
    @staticmethod
    def get_default():
        return GrabDisplay()

    def get_default_seat(self):
        return GrabSeat()


class GrabGdk:
    Display = GrabDisplay

    class SeatCapabilities:
        KEYBOARD = "keyboard"


class GrabSelf:
    def get_window(self):
        return "switcher-window"


real_gdk = mp.Gdk
mp.Gdk = GrabGdk
try:
    mp.windows_lib.is_wayland_session = lambda: True
    mp.Picker.on_map_grab_keyboard(GrabSelf(), None, None)
    check_eq("Wayland: no keyboard grab (it closed the switcher)", grabs, [])
    mp.windows_lib.is_wayland_session = lambda: False
    mp.Picker.on_map_grab_keyboard(GrabSelf(), None, None)
    check_eq("X11: the keyboard is grabbed, as before", [g[:2] for g in grabs], [("switcher-window", "keyboard")])
finally:
    mp.Gdk = real_gdk

mp.windows_lib.list_windows, mp.windows_lib.is_wayland_session, mp.windows_lib.activate_window = saved

print(f"\n{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
