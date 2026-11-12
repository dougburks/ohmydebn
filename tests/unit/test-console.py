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

# Wnck only sees X11 windows: in Cinnamon's Wayland session the console
# talks to XWayland, where its Alacritty runs (Linux Mint 27).
check_eq("Wayland with XWayland: X11", console.x11_backend({"WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0"}), True)
check_eq("Wayland by session type: X11", console.x11_backend({"XDG_SESSION_TYPE": "wayland", "DISPLAY": ":1"}), True)
check_eq("Wayland without XWayland: nothing to switch to", console.x11_backend({"WAYLAND_DISPLAY": "wayland-0"}), False)
check_eq("an X11 session: left as it is", console.x11_backend({"XDG_SESSION_TYPE": "x11", "DISPLAY": ":0"}), False)
check_eq("an empty WAYLAND_DISPLAY isn't Wayland", console.x11_backend({"WAYLAND_DISPLAY": "", "DISPLAY": ":0"}), False)

# 70% by 60%, centered in the work area (the monitor without the panel).
check_eq("centered in a work area below a 40px top panel",
         console.placement((0, 40, 2540, 1274)), (381, 295, 1778, 764))
check_eq("centered on a second monitor to the right",
         console.placement((1920, 0, 1920, 1080)), (1920 + 288, 216, 1344, 648))
check_eq("odd sizes round down and stay inside the area",
         console.placement((0, 0, 1001, 701)), (150, 140, 700, 420))

check_eq("its window class is the one gTile leaves floating", console.WM_CLASS, "OhMyDebnConsole")
check_eq("it runs ohmydebn-console-run", console.RUN, "/usr/share/ohmydebn/bin/ohmydebn-console-run")

# The backend must be chosen before Gdk is imported: PyGObject's Gdk
# overrides open the display on import, so choosing it afterwards (as the
# first fix did, with Gdk.set_allowed_backends) changed nothing and Wnck
# still found no screen. A stand-in gi records GDK_BACKEND as Gdk is
# imported, then stops main() at Gtk.init.
import tempfile  # noqa: E402
import types  # noqa: E402


class _Stop(Exception):
    pass


def backend_at_gdk_import(environ):
    seen = {}

    class Repository(types.ModuleType):
        def __getattr__(self, name):
            if name == "Gdk":
                seen["backend"] = os.environ.get("GDK_BACKEND")
            if name == "Gtk":
                def init(_argv):
                    seen["after"] = os.environ.get("GDK_BACKEND")
                    raise _Stop()
                return types.SimpleNamespace(init=init)
            return types.SimpleNamespace()

    fake_gi = types.ModuleType("gi")
    fake_gi.require_version = lambda *a: None
    fake_gi.repository = Repository("gi.repository")
    saved_modules = {k: sys.modules.get(k) for k in ("gi", "gi.repository")}
    saved_env = dict(os.environ)
    sys.modules["gi"], sys.modules["gi.repository"] = fake_gi, fake_gi.repository
    os.environ.clear()
    os.environ.update(environ, XDG_RUNTIME_DIR=tempfile.mkdtemp())
    try:
        console.main()
    except _Stop:
        pass
    finally:
        os.environ.clear()
        os.environ.update(saved_env)
        for k, v in saved_modules.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v
    return seen


seen = backend_at_gdk_import({"WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0"})
check_eq("Wayland: Gdk opens XWayland (GDK_BACKEND=x11 as it's imported)", seen.get("backend"), "x11")
check_eq("Wayland: GDK_BACKEND is gone again before anything is launched", seen.get("after"), None)
seen = backend_at_gdk_import({"WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0", "GDK_BACKEND": "wayland,x11"})
check_eq("Wayland: a GDK_BACKEND of the user's own is put back", seen.get("after"), "wayland,x11")
seen = backend_at_gdk_import({"XDG_SESSION_TYPE": "x11", "DISPLAY": ":0"})
check_eq("X11: Gdk's backend is left alone", seen.get("backend"), None)

print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
