#!/bin/bash
#
# Unit tests for the light intro's drawing in bin/ohmydebn-theme-intro-play
# on scaled (HiDPI) displays. With 2x display scaling the background filled
# only the top left quarter of the screen while the light and shimmer
# played: the images' server copies carry the window's scale, so they
# already drew at the logical size, and the drawing scaled the context down
# to device pixels on top of that.
#
# The real LightIntro.on_draw draws each frame into an image surface with
# the window's scale, as GTK hands a scaled window, through a stand-in
# window whose surfaces carry that scale as GDK's do. A frame at 2x must be
# the same picture as at 1x, at every point and every stage of the intro.
# No display is used.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-intro-play: the light intro on scaled displays ==="

OUTPUT=$(env -u DISPLAY -u WAYLAND_DISPLAY python3 - "$REPO_ROOT/bin/ohmydebn-theme-intro-play" 2>/dev/null <<'EOF'
import importlib.machinery
import importlib.util
import sys

import cairo

loader = importlib.machinery.SourceFileLoader("intro_play", sys.argv[1])
spec = importlib.util.spec_from_loader("intro_play", loader)
play = importlib.util.module_from_spec(spec)
loader.exec_module(play)
from gi.repository import GdkPixbuf, GLib  # noqa: E402

W, H = 160, 90


class Window:
    """GDK's create_similar_surface: logical size, the window's scale."""

    def __init__(self, scale):
        self.scale = scale

    def create_similar_surface(self, content, width, height):
        fmt = cairo.FORMAT_A8 if content == cairo.CONTENT_ALPHA else cairo.FORMAT_RGB24
        surface = cairo.ImageSurface(fmt, width * self.scale, height * self.scale)
        surface.set_device_scale(self.scale, self.scale)
        return surface


class Area:
    def __init__(self, scale):
        self.scale = scale
        self.window = Window(scale)

    def get_scale_factor(self):
        return self.scale

    def get_allocated_width(self):
        return W

    def get_allocated_height(self):
        return H

    def get_window(self):
        return self.window


# A picture with something different everywhere: red across, green down,
# and wider than the screen, so the cover crop shows too.
pw, ph = 320, 120
data = bytearray()
for y in range(ph):
    for x in range(pw):
        data += bytes((x * 255 // (pw - 1), y * 255 // (ph - 1), 96))
pixbuf = GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(bytes(data)), GdkPixbuf.Colorspace.RGB,
                                         False, 8, pw, ph, pw * 3)


def frame(scale, t):
    intro = play.LightIntro.__new__(play.LightIntro)
    intro.pixbuf = pixbuf
    intro.surfaces = {}
    intro.started = GLib.get_monotonic_time() - int(t * 1e6)
    intro.fade_out = lambda _ms: None
    target = cairo.ImageSurface(cairo.FORMAT_RGB24, W * scale, H * scale)
    target.set_device_scale(scale, scale)
    intro.on_draw(Area(scale), cairo.Context(target), 0)
    target.flush()
    return target


def pixel(surface, fx, fy):
    """The pixel at a fraction of the way across and down, as (r, g, b)."""
    x = min(surface.get_width() - 1, int(fx * surface.get_width()))
    y = min(surface.get_height() - 1, int(fy * surface.get_height()))
    i = y * surface.get_stride() + x * 4
    b, g, r = surface.get_data()[i:i + 3]
    return r, g, b


stages = {
    "twilight": play.LIGHT[0] / 2,
    "light arriving": (play.LIGHT[0] + play.LIGHT[1]) / 2,
    "shimmer": (play.SHIMMER[0] + play.SHIMMER[1]) / 2,
    "end": play.LIGHT_DURATION + 1,
}
points = [(fx / 8, fy / 8) for fx in range(1, 8) for fy in range(1, 8)] + [(0.01, 0.01), (0.99, 0.99)]
for name, t in stages.items():
    one, two = frame(1, t), frame(2, t)
    worst = max(abs(a - b) for p in points for a, b in zip(pixel(one, *p), pixel(two, *p)))
    print(f"{name} worst={worst}")
    corner = pixel(two, 0.99, 0.99)
    print(f"{name} corner-black={'yes' if corner == (0, 0, 0) else 'no'}")
EOF
)

for stage in "twilight" "light arriving" "shimmer" "end"; do
  worst=$(sed -n "s/^$stage worst=//p" <<<"$OUTPUT")
  assert_eq "2x, $stage: the same picture as at 1x" "yes" \
    "$([[ -n "$worst" && "$worst" -le 12 ]] && echo yes || echo "no (largest difference: ${worst:-none})")"
  assert_eq "2x, $stage: the bottom right corner isn't left black" "no" \
    "$(sed -n "s/^$stage corner-black=//p" <<<"$OUTPUT")"
done

test_summary
