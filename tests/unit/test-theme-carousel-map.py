#!/usr/bin/python3
#
# Tests for bin/ohmydebn-theme-carousel's "map-event" handler, which calls
# present() so the newly mapped window gets keyboard focus. On GTK3's
# Wayland backend (Cinnamon's Wayland session, seen on Linux Mint 27),
# present() on a mapped window emits "map-event" again, so the handler
# called itself without end: the carousel never appeared, ran at full CPU,
# and one more piled up on every press of Ctrl+Super+T. The handler and
# its wiring are taken from the script's own source and run against a
# stand-in window that re-emits "map-event" on present() as Wayland does,
# so neither GTK nor a display is needed.

import ast
import os
import sys
import textwrap

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCRIPT = os.path.join(REPO_ROOT, "bin", "ohmydebn-theme-carousel")

TESTS_RUN = 0
TESTS_FAILED = 0


def check(desc, condition, detail=""):
    global TESTS_RUN, TESTS_FAILED
    TESTS_RUN += 1
    if condition:
        print(f"  ok - {desc}")
    else:
        print(f"  FAIL - {desc}{f' ({detail})' if detail else ''}")
        TESTS_FAILED += 1


print("=== bin/ohmydebn-theme-carousel: map-event handler ===")

tree = ast.parse(open(SCRIPT).read())
handler_src = None
connects_map_event = False
for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef) and node.name == "on_map_present":
        handler_src = ast.get_source_segment(open(SCRIPT).read(), node)
    # self.connect("map-event", self.on_map_present)
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "connect"
            and len(node.args) == 2 and isinstance(node.args[0], ast.Constant) and node.args[0].value == "map-event"
            and isinstance(node.args[1], ast.Attribute) and node.args[1].attr == "on_map_present"):
        connects_map_event = True

check("the window connects map-event to on_map_present", connects_map_event)
check("on_map_present is in the script", handler_src is not None)
if handler_src is None:
    print(f"\n{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
    sys.exit(1)

namespace = {}
exec(compile(textwrap.dedent(handler_src), SCRIPT, "exec"), namespace)
on_map_present = namespace["on_map_present"]

# More re-entries than this is the loop: the real one ran ~9,400 times in
# 1.5 s before anyone noticed.
LIMIT = 50


class FakeWindow:
    """Just enough of a Gtk.Window: signal handlers, and present(), which
    re-emits map-event on a mapped window when wayland is set."""

    def __init__(self, wayland):
        self.wayland = wayland
        self.handlers = []
        self.presents = 0
        self.depth = 0
        self.runaway = False
        self.on_map_present = on_map_present.__get__(self)

    def connect(self, signal, fn):
        self.handlers.append((signal, fn))

    def disconnect_by_func(self, fn):
        self.handlers = [(s, f) for s, f in self.handlers if f != fn]

    def emit(self, signal):
        self.depth += 1
        if self.depth > LIMIT:
            self.runaway = True
            return
        for s, fn in list(self.handlers):
            if s == signal:
                fn(self, None)

    def present(self):
        self.presents += 1
        if self.wayland:
            self.emit("map-event")


for wayland in (True, False):
    session = "Wayland" if wayland else "X11"
    w = FakeWindow(wayland)
    w.connect("map-event", w.on_map_present)
    w.emit("map-event")
    check(f"{session}: map-event doesn't loop", not w.runaway, f"{w.presents} present() calls")
    check(f"{session}: present() once, for focus", w.presents == 1, f"{w.presents} calls")
    w.emit("map-event")  # mapped again later (unminimized, say)
    check(f"{session}: the handler is gone after its one run", w.presents == 1, f"{w.presents} calls")

print(f"\n{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
