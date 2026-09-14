#!/usr/bin/python3
#
# ohmydebn_theme_colors.py: the shared reader for the current theme's
# GUI palette (~/.config/ohmydebn/current/picker-colors - the small
# key=value file ohmydebn-theme-set-picker rewrites on every theme
# change). Four keys, in the roles ohmydebn-menu-picker established:
# bg0 = window scrim, bg1 = solid surface, bg3 = accent, fg0 =
# foreground. Grew out of ohmydebn-update-gui's own loader once
# ohmydebn_speedtest_common.py became a second consumer of the same
# parsing - ohmydebn-menu-picker predates all of this and keeps its own
# reader (it wants CSS strings directly and carries extra picker-only
# styling around them), so the palette *file* stays the single source of
# truth even though that one reader isn't unified here.
#
# Not a menu entry itself - imported only, the same role
# ohmydebn_speedtest_common.py plays for the dial widget (and the same
# reason for the underscored, .py-suffixed name: it must be a valid
# `import` target, which a hyphenated name can never be).

import os

# Identical to ohmydebn-menu-picker's DEFAULT_COLORS, hex-encoded - the
# shared "no theme applied yet" fallback look.
DEFAULT_THEME_COLORS = {
    "bg0": "#141418F2",
    "bg1": "#141418",
    "bg3": "#5A5ADCF2",
    "fg0": "#E6E6E6",
}


def parse_hex_color(value):
    """"#RRGGBB" or "#RRGGBBAA" (the two shapes picker-colors carries) ->
    (r, g, b, a) floats in 0..1, or None for anything malformed - callers
    keep their default instead."""
    h = value.strip().lstrip("#")
    if len(h) not in (6, 8):
        return None
    try:
        r, g, b = (int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
        a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    except ValueError:
        return None
    return (r, g, b, a)


def css_rgba(color, alpha=None):
    """(r, g, b, a) floats -> a CSS rgba() string; `alpha` overrides the
    color's own alpha, for the dimmed foreground variants the GUIs use."""
    r, g, b, a = color
    if alpha is not None:
        a = alpha
    return f"rgba({round(r * 255)}, {round(g * 255)}, {round(b * 255)}, {a:.3f})"


def relative_luminance(color):
    """WCAG relative luminance of an (r, g, b[, a]) color - alpha, if
    present, is ignored."""

    def linearize(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (linearize(c) for c in color[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(a, b):
    """WCAG contrast ratio (1..21) between two colors - for picking
    whichever of two palette colors reads best on a third (e.g. text on
    the accent-filled primary button, where a light accent wants bg1 and
    a dark accent wants fg0; no single fixed choice works across
    themes)."""
    la, lb = relative_luminance(a), relative_luminance(b)
    lighter, darker = max(la, lb), min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)


def load_theme_colors(path=None):
    """The current theme's palette as {key: (r, g, b, a)}. Read once at
    each GUI's startup, not live - every consumer's window lifetime (one
    update run, one speed test) is far shorter than a theme change could
    plausibly land in the middle of. Missing or malformed keys keep
    DEFAULT_THEME_COLORS' value, so a damaged file degrades to the
    picker's own fallback look, never a crash."""
    colors = {key: parse_hex_color(value) for key, value in DEFAULT_THEME_COLORS.items()}
    if path is None:
        path = os.path.expanduser("~/.config/ohmydebn/current/picker-colors")
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                key, _, value = line.strip().partition("=")
                if key in colors and value:
                    parsed = parse_hex_color(value)
                    if parsed is not None:
                        colors[key] = parsed
    except OSError:
        pass
    return colors
