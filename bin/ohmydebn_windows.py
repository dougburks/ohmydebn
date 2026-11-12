"""Open windows for the window switcher (Ctrl+Alt+Tab, ohmydebn-menu-picker
--windows), from Cinnamon itself.

The switcher used to list and activate windows through libwnck, which only
works with X11 windows: in Cinnamon's Wayland session, where most apps are
Wayland windows, it found no screen at all and crashed before showing
anything. gTile@OhMyDebn runs inside Cinnamon, which sees every window in
either session, and offers ListWindows and ActivateWindow on its D-Bus
interface (org.gTile.Control), most recently used window first.

No GTK here, so tests/unit/test-windows.py runs it without a display: the
D-Bus call goes through a function the tests replace."""

import fcntl
import os
from collections import namedtuple

GTILE_BUS_NAME = "org.gTile.Control"
GTILE_OBJECT_PATH = "/org/gTile/Control"
GTILE_INTERFACE = "org.gTile.Control"
# A switcher that waits on D-Bus is a switcher that feels broken: gTile
# answers from Cinnamon's own process in milliseconds, so a second means
# it isn't there to answer.
DBUS_TIMEOUT_MS = 1000

SwitcherWindow = namedtuple("SwitcherWindow", "id title wm_class app_id icon")


def _gdbus_call(method, params, reply_type):
    """Calls one org.gTile.Control method on the session bus; returns the
    unpacked reply, or raises GLib.Error. Without auto-start: gTile is a
    Cinnamon extension, not a D-Bus service anything could start."""
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    reply = bus.call_sync(
        GTILE_BUS_NAME, GTILE_OBJECT_PATH, GTILE_INTERFACE, method,
        params, GLib.VariantType.new(reply_type) if reply_type else None,
        Gio.DBusCallFlags.NO_AUTO_START, DBUS_TIMEOUT_MS, None)
    return reply.unpack() if reply is not None else ()


def list_windows(call=_gdbus_call):
    """The windows a switcher offers, most recently used first (so the
    focused one first), as SwitcherWindows; None when gTile can't be asked
    (not installed, disabled, or a Cinnamon session without it)."""
    try:
        (rows,) = call("ListWindows", None, "(a(tssss))")
    except Exception:  # GLib.Error, or a reply of the wrong shape
        return None
    windows = []
    for row in rows:
        try:
            windows.append(SwitcherWindow(*row))
        except TypeError:
            continue
    return windows


def activate_window(window_id, call=_gdbus_call):
    """Brings that window to the front, switching workspace as needed.
    False when gTile couldn't (the window closed meanwhile, or gTile is
    gone): there's nothing more a switcher can do about either."""
    from gi.repository import GLib

    try:
        call("ActivateWindow", GLib.Variant("(t)", (window_id,)), None)
    except Exception:
        return False
    return True


def is_wayland_session(environ=None):
    """Whether this runs in a Wayland session, where libwnck can't stand in
    for gTile: there it sees only X11 windows, if any."""
    env = os.environ if environ is None else environ
    return bool(env.get("WAYLAND_DISPLAY")) or env.get("XDG_SESSION_TYPE") == "wayland"


def icon_candidates(window):
    """Icon names (or file paths) to try for a window's row, best first:
    its app's icon as Cinnamon matched it, then names derived from the
    window itself for windows Cinnamon couldn't match to an app (many
    apps name their icon after their WM_CLASS or .desktop file)."""
    names = []
    app_stem = window.app_id[:-len(".desktop")] if window.app_id.endswith(".desktop") else window.app_id
    for name in (window.icon, window.wm_class.lower(), window.wm_class, app_stem):
        if name and name not in names:
            names.append(name)
    return names


def claim_switcher(lock_path):
    """Makes this the one running switcher, or finds the one already open.
    On X11 the switcher grabs the keyboard, so further Tab taps reach it
    and never Cinnamon; on Wayland a client can't take the keyboard from
    the compositor, so each further Ctrl+Alt+Tab starts another switcher,
    which would open a second window with the first row selected again.
    Instead, a second switcher hands its tap to the first (signals it to
    move down a row) and exits.

    Returns (True, fd) when this one is the switcher - keep fd open for as
    long as it runs, which holds the lock - or (False, pid) for the one
    already running (pid None if it couldn't be read)."""
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        try:
            pid = int(os.pread(fd, 32, 0).decode().strip() or "0") or None
        except (OSError, ValueError):
            pid = None
        os.close(fd)
        return False, pid
    os.ftruncate(fd, 0)
    os.pwrite(fd, str(os.getpid()).encode(), 0)
    return True, fd


def switcher_lock_path(environ=None):
    """Where claim_switcher's lock lives: the user's runtime directory,
    private to them and cleared at logout, else their cache directory."""
    env = os.environ if environ is None else environ
    base = env.get("XDG_RUNTIME_DIR") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "ohmydebn-window-switcher.lock")
