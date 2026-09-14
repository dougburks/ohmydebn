#!/usr/bin/python3
#
# Shared GTK/Cairo dial widget and support code for
# ohmydebn-network-speedtest-gui and ohmydebn-disk-speedtest-gui - a
# recreation of Omarchy's own QML speed-test overlay
# (~/git/omarchy's shell/Ui/SpeedTestOverlay.qml, the "Quattro" checkout),
# which is itself explicitly "shared by the network and disk speed tests"
# per its own top comment; this file is that same sharing, just via a
# plain importable Python module instead of one shared QML component,
# since neither GUI is meant to be run as a standalone CLI tool the way
# every hyphenated bin/ohmydebn-* script is (hence the underscored,
# .py-suffixed name here instead of that convention - it needs to be a
# valid `import` target, which a name containing hyphens can never be).
#
# Not a menu entry itself - sourced only, the Python equivalent of
# bin/ohmydebn-menu-tree's own "Sourced only" role for bash.

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import GLib, Gtk

import cairo
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from ohmydebn_theme_colors import css_rgba, load_theme_colors  # noqa: E402

# Full-scale latch points for the dials, smallest first - same stops
# Omarchy's own overlay uses. The first stop is the base scale a fresh
# run starts from; a reading past 92% of the current scale jumps to the
# next stop up, so the needle/arc never quite pins at full deflection.
SCALE_STOPS = [100, 250, 500, 1000, 2500, 5000, 10000]

# Themed via the shared picker-colors palette (see
# ohmydebn_theme_colors.py) - the same four keys ohmydebn-menu-picker and
# ohmydebn-update-gui dress themselves in, read once at startup for the
# same one-short-window-lifetime reason as ever. This used to be a fixed
# near-black "onScrim" set copied from Omarchy's own overlay, on the
# argument that an arbitrary theme foreground couldn't be trusted for
# legibility against a fixed scrim - but with the background AND
# foreground both coming from the same palette (a pair every theme
# designs for contrast, since the whole picker UI depends on it), that
# worry no longer applies, and ohmydebn-update-gui proved the fully
# themed look. The dial accent (value arc, glow, needle) was
# theme-derived (bg3) all along, matching Omarchy's own Color.accent; the
# fixed alpha ramps on the foreground below preserve the original
# overlay's tick/text hierarchy exactly. COLOR_ERROR stays fixed -
# semantic, not decorative.
_PALETTE = load_theme_colors()
_FG = _PALETTE["fg0"][:3]
COLOR_TRACK = (*_FG, 0.14)
COLOR_TICK_MINOR = (*_FG, 0.12)
COLOR_TICK_MAJOR = (*_FG, 0.3)
COLOR_TEXT = (*_FG, 1)
COLOR_TEXT_DIM = (*_FG, 0.55)
COLOR_ERROR = (1, 0.42, 0.42, 1)
COLOR_ACCENT = _PALETTE["bg3"][:3]

# The dial's Cairo-drawn text (readout, unit, direction label) - the
# same face the window CSS below and every other themed OhMyDebn GUI
# uses; cairo's toy font API resolves it through fontconfig.
FONT_FAMILY = "CaskaydiaMono Nerd Font"

DIAL_START_DEG = 135
DIAL_SWEEP_DEG = 270
TICK_COUNT = 46


def expand_scale(current_full_scale, value):
    for stop in SCALE_STOPS:
        if value <= stop * 0.92:
            return max(current_full_scale, stop)
    return SCALE_STOPS[-1]


def format_reading(value):
    if value < 10:
        return f"{value:.1f}"
    return f"{value:,.0f}"


class SpeedDial(Gtk.DrawingArea):
    """One dial: an open 270-degree scale (gap at the bottom, matching
    Omarchy's own PathAngleArc convention - cairo's own arc() angles
    already increase clockwise from 3 o'clock the same way, so no extra
    conversion is needed), a faint tick ring, a glowing accent value arc,
    a needle that fades toward the pivot, and a digital readout in the
    center. `shown` eases toward `value` on a timer instead of snapping,
    the same "glide between live readings" feel as the QML version's own
    Behavior-on-shown animation. `unit` is a label only (e.g. "Mbps" for
    network, "MB/s" for disk) - it plays no part in the math, callers are
    responsible for feeding `value` in whatever unit they name here."""

    def __init__(self, label, unit):
        super().__init__()
        self.label = label
        self.unit = unit
        self.value = 0.0
        self.shown = 0.0
        self.full_scale = SCALE_STOPS[0]
        self.live = False
        self.set_size_request(260, 260)
        self.connect("draw", self._on_draw)
        GLib.timeout_add(33, self._animate_tick)

    def set_value(self, value):
        self.value = value
        self.full_scale = expand_scale(self.full_scale, value)
        self.live = True

    def stop(self):
        self.live = False

    def reset(self):
        self.value = self.shown = 0.0
        self.full_scale = SCALE_STOPS[0]
        self.live = False

    def _animate_tick(self):
        # Simple exponential ease toward the real value - cheap, and
        # smooth enough at 30fps that a once-a-second reading doesn't
        # visibly snap into place.
        delta = self.value - self.shown
        if abs(delta) > 0.05:
            self.shown += delta * 0.15
            self.queue_draw()
        return GLib.SOURCE_CONTINUE

    def _on_draw(self, _widget, cr):
        w = self.get_allocated_width()
        h = self.get_allocated_height()
        cx, cy = w / 2, h / 2
        diameter = min(w, h)
        radius = diameter / 2 - 14
        arc_width = 5

        start = math.radians(DIAL_START_DEG)
        sweep = math.radians(DIAL_SWEEP_DEG)
        fraction = 0.0
        if self.full_scale > 0:
            fraction = max(0.0, min(1.0, self.shown / self.full_scale))

        # Track: the full scale, always visible, dim.
        cr.set_line_cap(cairo.LINE_CAP_ROUND)
        cr.set_line_width(arc_width)
        cr.set_source_rgba(*COLOR_TRACK)
        cr.arc(cx, cy, radius, start, start + sweep)
        cr.stroke()

        if fraction > 0.004:
            # Soft under-glow, wider and fainter, standing in for the
            # backlit ring of a real instrument cluster.
            cr.set_line_width(arc_width * 3)
            cr.set_source_rgba(COLOR_ACCENT[0], COLOR_ACCENT[1], COLOR_ACCENT[2], 0.18)
            cr.arc(cx, cy, radius, start, start + sweep * fraction)
            cr.stroke()

            cr.set_line_width(arc_width)
            cr.set_source_rgba(*COLOR_ACCENT, 1)
            cr.arc(cx, cy, radius, start, start + sweep * fraction)
            cr.stroke()

        # Faint tick ring just inside the arc; every fifth tick major.
        tick_radius = radius - arc_width * 2
        for i in range(TICK_COUNT):
            angle = start + (i / (TICK_COUNT - 1)) * sweep
            major = i % 5 == 0
            length = 10 if major else 6
            color = COLOR_TICK_MAJOR if major else COLOR_TICK_MINOR
            x0 = cx + tick_radius * math.cos(angle)
            y0 = cy + tick_radius * math.sin(angle)
            x1 = cx + (tick_radius - length) * math.cos(angle)
            y1 = cy + (tick_radius - length) * math.sin(angle)
            cr.set_source_rgba(*color)
            cr.set_line_width(2 if major else 1)
            cr.move_to(x0, y0)
            cr.line_to(x1, y1)
            cr.stroke()

        # Hubless needle: fades toward the pivot via a linear gradient
        # along its own length, so it reads as floating rather than
        # anchored to a hub.
        needle_angle = start + fraction * sweep
        needle_len = radius * 0.62
        inner = 18
        x0 = cx + inner * math.cos(needle_angle)
        y0 = cy + inner * math.sin(needle_angle)
        x1 = cx + needle_len * math.cos(needle_angle)
        y1 = cy + needle_len * math.sin(needle_angle)
        pattern = cairo.LinearGradient(x0, y0, x1, y1)
        pattern.add_color_stop_rgba(0.0, *COLOR_ACCENT, 1)
        pattern.add_color_stop_rgba(0.55, *COLOR_ACCENT, 1)
        pattern.add_color_stop_rgba(1.0, *COLOR_ACCENT, 0)
        cr.set_source(pattern)
        cr.set_line_width(3)
        cr.move_to(x0, y0)
        cr.line_to(x1, y1)
        cr.stroke()

        # Center digital readout.
        opacity = 1.0 if (self.live or self.value > 0) else 0.5
        reading_text = format_reading(self.shown)
        cr.select_font_face(FONT_FAMILY, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(diameter * 0.16)
        extents = cr.text_extents(reading_text)
        cr.set_source_rgba(COLOR_TEXT[0], COLOR_TEXT[1], COLOR_TEXT[2], opacity)
        cr.move_to(cx - extents.width / 2 - extents.x_bearing, cy - 4)
        cr.show_text(reading_text)

        cr.select_font_face(FONT_FAMILY, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        cr.set_font_size(diameter * 0.06)
        extents = cr.text_extents(self.unit)
        cr.set_source_rgba(COLOR_TEXT_DIM[0], COLOR_TEXT_DIM[1], COLOR_TEXT_DIM[2], opacity)
        cr.move_to(cx - extents.width / 2 - extents.x_bearing, cy + diameter * 0.10)
        cr.show_text(self.unit)

        # Direction label, in the gap at the bottom of the scale.
        cr.select_font_face(FONT_FAMILY, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(diameter * 0.055)
        extents = cr.text_extents(self.label)
        cr.set_source_rgba(*COLOR_TEXT_DIM)
        cr.move_to(cx - extents.width / 2 - extents.x_bearing, cy + radius - 4)
        cr.show_text(self.label)

        return False


def apply_theme_css():
    """Shared CSS for either speed test's window: the current theme's
    scrim behind the dials, its foreground for labels (dimmed for the
    bold uppercase title), and the same CaskaydiaMono face at 12pt every
    other themed OhMyDebn GUI uses - see the palette comment above for
    the themed-vs-fixed history (this used to be apply_dark_scrim_css,
    hardcoding Omarchy's near-black onScrim palette)."""
    from gi.repository import Gdk  # deferred: only this function needs Gdk.Screen

    css = f"""
    window {{ background-color: {css_rgba(_PALETTE["bg0"])}; }}
    label {{ color: {css_rgba(_PALETTE["fg0"], 0.85)}; }}
    .speedtest-title {{ font-weight: bold; letter-spacing: 2px; color: {css_rgba(_PALETTE["fg0"], 0.55)}; }}
    * {{ font-family: "{FONT_FAMILY}"; font-size: 12pt; }}
    """.encode("utf-8")
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )


def error_markup(message):
    """Wraps a status message in the shared urgent-red span color, for
    Gtk.Label.set_markup() - the one fixed, theme-independent color left
    in this module's palette, matching Omarchy's own onScrimUrgent."""
    color = "#{:02x}{:02x}{:02x}".format(*(round(c * 255) for c in COLOR_ERROR[:3]))
    return f'<span foreground="{color}">{GLib.markup_escape_text(message)}</span>'
