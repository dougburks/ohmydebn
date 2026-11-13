#!/bin/bash
#
# Unit tests for the theme intro's windows in bin/ohmydebn-theme-intro-play.
# They were full screen and kept above everything, so an intro hid the
# whole desktop, open windows and panel included; Omarchy plays its intros
# in the wallpaper layer, under the windows. Each window is now a
# desktop-type window covering its monitor: below every other window, on
# every workspace, never taking the keyboard, and skipped with a click. In
# a Wayland session it opens through XWayland, the only way to ask for that.
#
# make_window runs against stand-ins for Gtk.Window and the monitors, so no
# display is used.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-intro-play: the intro's windows ==="

# load_play <python> [env arguments...]: runs <python> with the player
# loaded as `play`, in the environment env(1) makes of the rest.
load_play() {
  local code=$1
  shift
  env "$@" python3 - "$REPO_ROOT/bin/ohmydebn-theme-intro-play" "$code" 2>/dev/null <<'EOF'
import importlib.machinery
import importlib.util
import sys

loader = importlib.machinery.SourceFileLoader("intro_play", sys.argv[1])
spec = importlib.util.spec_from_loader("intro_play", loader)
play = importlib.util.module_from_spec(spec)
loader.exec_module(play)
exec(sys.argv[2])
EOF
}

WINDOW=$(load_play '
calls = []

class Geometry:
    x, y, width, height = 1920, 0, 2560, 1440

class Monitor:
    def get_geometry(self):
        return Geometry()

class Window:
    def __getattr__(self, name):
        # Logged as name(args): an enum by its nick, a callback left out.
        def record(*args):
            shown = [getattr(a, "value_nick", None) or repr(a) for a in args if not callable(a)]
            calls.append(name + "(" + ", ".join(shown) + ")")
            # Itself again, for chained calls (get_style_context().add_class).
            return self
        return record

play.Gtk.Window = Window
intro = play.Intro()
intro.monitors = lambda: [Monitor(), Monitor()]
intro.make_window(1, object())
print("\n".join(calls))
' -u DISPLAY -u WAYLAND_DISPLAY)

assert_contains "a desktop window, below every other window and the panel" "$WINDOW" "set_type_hint(desktop)"
assert_not_contains "not kept above everything" "$WINDOW" "set_keep_above"
assert_not_contains "not full screen" "$WINDOW" "fullscreen"
assert_contains "covers its monitor: its size" "$WINDOW" "set_default_size(2560, 1440)"
assert_contains "covers its monitor: its place" "$WINDOW" "move(1920, 0)"
assert_contains "on every workspace" "$WINDOW" "stick()"
assert_contains "never takes the keyboard" "$WINDOW" "set_accept_focus(False)"
assert_contains "not even when it appears" "$WINDOW" "set_focus_on_map(False)"
assert_contains "a click skips it" "$WINDOW" "connect('button-press-event')"
assert_not_contains "a keypress doesn't (keys stay with the window in front)" "$WINDOW" "key-press-event"
assert_not_contains "the pointer isn't hidden" "$WINDOW" "cursor"
assert_contains "kept out of the window list" "$WINDOW" "set_skip_taskbar_hint(True)"

# Which backend the windows open with, in the environment given.
backend() {
  load_play 'import os; print(os.environ.get("GDK_BACKEND", "default"))' -u GDK_BACKEND "$@"
}
assert_eq "Wayland session: through XWayland" "x11" \
  "$(backend DISPLAY=:97 WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland)"
assert_eq "Wayland session without XWayland: left as it is" "default" \
  "$(backend -u DISPLAY WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland)"
assert_eq "X11 session: left as it is" "default" \
  "$(backend -u WAYLAND_DISPLAY DISPLAY=:97 XDG_SESSION_TYPE=x11)"

# The ready file: touched as the first frame goes on screen, the moment
# "ready" is said, so the theme carousel (above the windows the intro
# plays behind) knows to get out of the way.
RUNTIME=$(mktemp -d)
READY_SAID=$(load_play 'play.Intro().send_ready()' -u DISPLAY -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RUNTIME")
assert_eq "ready: still said on stdout, for ohmydebn-theme-intro" "ready" "$READY_SAID"
assert_eq "ready: the ready file is touched" "yes" "$([ -f "$RUNTIME/ohmydebn-theme-intro.ready" ] && echo yes || echo no)"
rm -rf "$RUNTIME"
RUNTIME=$(mktemp -d)
load_play 'play.Intro()' -u DISPLAY -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RUNTIME" >/dev/null
assert_eq "ready: not touched before then" "no" "$([ -f "$RUNTIME/ohmydebn-theme-intro.ready" ] && echo yes || echo no)"
rm -rf "$RUNTIME"

test_summary
