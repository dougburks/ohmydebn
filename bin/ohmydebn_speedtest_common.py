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

# Full-scale latch points for the dials, smallest first - same stops
# Omarchy's own overlay uses. The first stop is the base scale a fresh
# run starts from; a reading past 92% of the current scale jumps to the
# next stop up, so the needle/arc never quite pins at full deflection.
SCALE_STOPS = [100, 250, 500, 1000, 2500, 5000, 10000]

# Fixed, not theme-derived - Omarchy's own overlay makes the same choice
# for its scrim and text ("onScrim"/"onScrimDim" in its own QML: a fixed
# near-black background needs a fixed light palette on top of it, not
# whatever a theme's foreground color happens to be, or legibility would
# depend on luck). Its dial accent (the value arc, glow, and needle) is
# the one color that IS theme-derived there, via its own Color.accent -
# COLOR_ACCENT below matches that, not this fixed set.
COLOR_BG = (0.04, 0.04, 0.05)
COLOR_TRACK = (1, 1, 1, 0.14)
COLOR_TICK_MINOR = (1, 1, 1, 0.12)
COLOR_TICK_MAJOR = (1, 1, 1, 0.3)
COLOR_TEXT = (1, 1, 1, 1)
COLOR_TEXT_DIM = (1, 1, 1, 0.55)
COLOR_ERROR = (1, 0.42, 0.42, 1)


def load_accent_color():
    """The dial's value arc/glow/needle color - matches ohmydebn-menu-picker's
    own "bg3" theme color (every ohmydebn theme's accent/border tone,
    rewritten fresh on every theme change by ohmydebn-theme-set-picker),
    the same way Omarchy's own overlay pulls its dial accent from its
    Color.accent singleton rather than hardcoding one. Read once at
    startup, not re-read live - either speed test window's lifetime (one
    run) is far shorter than a theme change could plausibly land in the
    middle of. Falls back to a fixed blue if the theme file is missing or
    unreadable, matching ohmydebn-menu-picker's own DEFAULT_COLORS
    fallback for the same "bg3" key."""
    default = (0.40, 0.69, 1.0)
    path = os.path.expanduser("~/.config/ohmydebn/current/picker-colors")
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                key, _, value = line.strip().partition("=")
                if key != "bg3" or not value:
                    continue
                hex_value = value.lstrip("#")
                if len(hex_value) < 6:
                    continue
                return (
                    int(hex_value[0:2], 16) / 255,
                    int(hex_value[2:4], 16) / 255,
                    int(hex_value[4:6], 16) / 255,
                )
    except OSError:
        pass
    return default


COLOR_ACCENT = load_accent_color()

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
        cr.select_font_face("sans-serif", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(diameter * 0.16)
        extents = cr.text_extents(reading_text)
        cr.set_source_rgba(COLOR_TEXT[0], COLOR_TEXT[1], COLOR_TEXT[2], opacity)
        cr.move_to(cx - extents.width / 2 - extents.x_bearing, cy - 4)
        cr.show_text(reading_text)

        cr.select_font_face("sans-serif", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        cr.set_font_size(diameter * 0.06)
        extents = cr.text_extents(self.unit)
        cr.set_source_rgba(COLOR_TEXT_DIM[0], COLOR_TEXT_DIM[1], COLOR_TEXT_DIM[2], opacity)
        cr.move_to(cx - extents.width / 2 - extents.x_bearing, cy + diameter * 0.10)
        cr.show_text(self.unit)

        # Direction label, in the gap at the bottom of the scale.
        cr.select_font_face("sans-serif", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(diameter * 0.055)
        extents = cr.text_extents(self.label)
        cr.set_source_rgba(*COLOR_TEXT_DIM)
        cr.move_to(cx - extents.width / 2 - extents.x_bearing, cy + radius - 4)
        cr.show_text(self.label)

        return False


def apply_dark_scrim_css():
    """Shared CSS for either speed test's window: near-black background,
    dim-white labels, a dimmer bold uppercase title - the same fixed
    "onScrim" palette Omarchy's own overlay uses (see COLOR_BG's own
    comment for why fixed, not theme-derived, is the deliberate choice
    here)."""
    from gi.repository import Gdk  # deferred: only this function needs Gdk.Screen

    bg = ", ".join(str(round(c * 255)) for c in COLOR_BG)
    css = f"""
    window {{ background-color: rgb({bg}); }}
    label {{ color: rgba(255, 255, 255, 0.85); }}
    .speedtest-title {{ font-weight: bold; letter-spacing: 2px; color: rgba(255, 255, 255, 0.55); }}
    """.encode("utf-8")
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )


def error_markup(message):
    """Wraps a status message in the shared urgent-red span color, for
    Gtk.Label.set_markup() - the one color in this palette that isn't
    plain white/dim-white, matching Omarchy's own onScrimUrgent."""
    color = "#{:02x}{:02x}{:02x}".format(*(round(c * 255) for c in COLOR_ERROR[:3]))
    return f'<span foreground="{color}">{GLib.markup_escape_text(message)}</span>'
