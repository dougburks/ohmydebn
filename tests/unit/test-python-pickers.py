#!/usr/bin/python3
#
# Pure-logic regression tests for the GTK pickers/carousels built this
# session: icon/label parsing, .desktop parsing/filtering, exec
# field-code stripping, theme/background enumeration and fallback, and
# cover-fit image math. Deliberately excludes anything that needs a real X
# display - resolve_icon()/load_apps()/load_windows()/get_monitor_geometry()
# all call Gtk.IconTheme.get_default()/Gdk.Display.get_default(), and both
# return None with no display (confirmed by hand, not assumed), crashing
# the very next call - so this suite runs the same with or without DISPLAY
# set. GdkPixbuf load/save/scale, by contrast, was confirmed to work fine
# with no display at all, so the cover-fit math is covered.

import os
import shutil
import sys
import tempfile
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


def load(name):
    return SourceFileLoader(name, os.path.join(BIN, name)).load_module()


print("=== ohmydebn-menu-picker (pure logic) ===")
mp = load("ohmydebn-menu-picker")

# Regression test: icon/label splitting must preserve the original
# separator instead of hardcoding two spaces - a literal "  " here once
# silently produced an empty label for every single-space wide-glyph item
# (e.g. "🔍︎ Cybersecurity"), which then matched no case arm in
# show_install_menu and bounced back to the parent menu instead of opening
# the Cybersecurity submenu - a real bug fixed earlier this session.
rows = mp.load_categories("🔍︎ Cybersecurity\n  Capture")
check_eq("wide-glyph single-space icon: label", rows[0][1], "Cybersecurity")
check("wide-glyph single-space icon: display preserves single space", rows[0][0] == "🔍︎ Cybersecurity")
check_eq("narrow PUA double-space icon: label", rows[1][1], "Capture")
check("narrow PUA double-space icon: display preserves two spaces", rows[1][0] == "  Capture")

# bash's literal two-char "\n" (not a real newline) must split into
# separate rows too, matching how ohmydebn-menu embeds multi-item strings.
rows = mp.load_categories("  Capture\\n  Style")
check_eq("literal backslash-n splits into rows: count", len(rows), 2)
check_eq("literal backslash-n splits into rows: second label", rows[1][1], "Style")

# find_submenu_labels: a category leads to a submenu iff some leaf display
# uses it as a breadcrumb prefix (flatten only emits leaves, so "Capture"
# appearing as "Capture > ..." means Capture recursed; appearing exactly
# means it's a leaf itself).
check_eq(
    "find_submenu_labels: label with child leaves is marked",
    mp.find_submenu_labels(["Capture"], ["Capture > Screenshot > Region", "Capture > Color"]),
    {"Capture"},
)
check_eq(
    "find_submenu_labels: leaf-only label is not marked",
    mp.find_submenu_labels(["Style"], ["Style"]),
    set(),
)
check_eq(
    "find_submenu_labels: plain-prefix leaf does not false-match",
    mp.find_submenu_labels(["Media"], ["Media Player > x"]),
    set(),
)
check_eq(
    "find_submenu_labels: nested level marks only the recursing label",
    mp.find_submenu_labels(["Browser", "Package"], ["Browser > Brave Origin (minimal)", "Package"]),
    {"Browser"},
)

# Regression test: populate()'s submenu-marker check (`self.mode == "menu"
# and value in self.submenu_labels`) crashed the entire app launcher
# (Super+R -> Picker(mode="apps")) before the `self.mode == "menu"` guard
# existed. apps mode's value is (exec_tokens, desktop_id) - see
# load_apps() - where exec_tokens is a list, making the whole tuple
# unhashable; `x in a_set` hashes x before it even looks at the set's
# contents, so the bare membership check raised TypeError even against
# Picker's own empty submenu_labels (set() for every non-menu mode - see
# Picker.__init__) rather than just failing to match. Exercises the exact
# guarded expression from populate() directly rather than constructing a
# real Picker - this suite is deliberately display-free (see the header
# comment); the live crash itself (and this fix resolving it) was also
# confirmed by hand running `python3 bin/ohmydebn-menu-picker --apps`
# under a real X display.
apps_value = (["x-terminal-emulator", "-e", "htop"], "htop.desktop")
try:
    guarded_result = "apps" == "menu" and apps_value in set()
    check("populate() submenu-marker guard: apps-mode value does not crash", True)
except TypeError:
    check("populate() submenu-marker guard: apps-mode value does not crash", False)

check_eq("_strip_exec_field_codes: strips %u", mp._strip_exec_field_codes("firefox %u"), ["firefox"])
check_eq(
    "_strip_exec_field_codes: strips multiple field codes",
    mp._strip_exec_field_codes("app %f %F %u %U %i %c %k"), ["app"],
)
check_eq(
    "_strip_exec_field_codes: keeps real args",
    mp._strip_exec_field_codes("app --flag value"), ["app", "--flag", "value"],
)
check_eq(
    "_strip_exec_field_codes: unescapes %% to a literal %",
    mp._strip_exec_field_codes("app --percent=50%%"), ["app", "--percent=50%"],
)
check_eq(
    "_strip_exec_field_codes: respects quoted args with spaces",
    mp._strip_exec_field_codes('app --title "My App" %f'), ["app", "--title", "My App"],
)

scratch = tempfile.mkdtemp(prefix="ohmydebn-test-")
try:
    def write_desktop(name, content):
        path = os.path.join(scratch, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return path

    normal = write_desktop(
        "normal.desktop",
        "[Desktop Entry]\nType=Application\nName=Test App\nExec=testapp %U\nIcon=test-icon\n",
    )
    entry = mp._parse_desktop_file(normal, set())
    check("_parse_desktop_file: normal entry parses", entry is not None)
    check_eq("_parse_desktop_file: name", entry[0], "Test App")
    check_eq("_parse_desktop_file: exec tokens (field code stripped)", entry[1], ["testapp"])
    check_eq("_parse_desktop_file: icon", entry[2], "test-icon")

    nodisplay = write_desktop(
        "nodisplay.desktop",
        "[Desktop Entry]\nType=Application\nName=Hidden App\nExec=hiddenapp\nNoDisplay=true\n",
    )
    check("_parse_desktop_file: NoDisplay=true is excluded", mp._parse_desktop_file(nodisplay, set()) is None)

    hidden = write_desktop(
        "hidden.desktop",
        "[Desktop Entry]\nType=Application\nName=Hidden App 2\nExec=hiddenapp2\nHidden=true\n",
    )
    check("_parse_desktop_file: Hidden=true is excluded", mp._parse_desktop_file(hidden, set()) is None)

    terminal = write_desktop(
        "terminal.desktop",
        "[Desktop Entry]\nType=Application\nName=Terminal App\nExec=vim %f\nTerminal=true\n",
    )
    entry = mp._parse_desktop_file(terminal, set())
    check_eq(
        "_parse_desktop_file: Terminal=true wraps in x-terminal-emulator -e",
        entry[1], ["x-terminal-emulator", "-e", "vim"],
    )

    only_show = write_desktop(
        "onlyshow.desktop",
        "[Desktop Entry]\nType=Application\nName=Cinnamon Only\nExec=cinnamonapp\nOnlyShowIn=GNOME;\n",
    )
    check(
        "_parse_desktop_file: OnlyShowIn excludes a non-matching desktop",
        mp._parse_desktop_file(only_show, {"X-Cinnamon"}) is None,
    )
    check(
        "_parse_desktop_file: OnlyShowIn includes a matching desktop",
        mp._parse_desktop_file(only_show, {"GNOME"}) is not None,
    )

    not_show = write_desktop(
        "notshow.desktop",
        "[Desktop Entry]\nType=Application\nName=Not On Cinnamon\nExec=someapp\nNotShowIn=X-Cinnamon;\n",
    )
    check(
        "_parse_desktop_file: NotShowIn excludes a matching desktop",
        mp._parse_desktop_file(not_show, {"X-Cinnamon"}) is None,
    )
finally:
    shutil.rmtree(scratch)

check_eq("hex_to_rgba: 6-digit hex has full opacity", mp.hex_to_rgba("#2e3440"), "rgba(46, 52, 64, 1.000)")
check_eq(
    "hex_to_rgba: 8-digit hex applies the trailing alpha byte",
    mp.hex_to_rgba("2e3440F2"), "rgba(46, 52, 64, 0.949)",
)

# load_theme_colors() reads ~/.config/ohmydebn/current/picker-colors, a
# hardcoded path built inline (not a module constant), so this redirects
# HOME for the duration of the test rather than monkeypatching a constant
# like the theme-carousel tests below do - this also exercises the real
# os.path.expanduser() path construction, not just the parsing after it.
old_home = os.environ.get("HOME")
fake_home = tempfile.mkdtemp(prefix="ohmydebn-test-home-")
try:
    os.environ["HOME"] = fake_home
    colors_dir = os.path.join(fake_home, ".config", "ohmydebn", "current")
    os.makedirs(colors_dir)
    picker_colors_path = os.path.join(colors_dir, "picker-colors")
    with open(picker_colors_path, "w", encoding="utf-8") as f:
        f.write("bg0=#2e3440F2\nbg1=#2e3440\nbg3=#81a1c1F2\nfg0=#d8dee9\n")

    colors = mp.load_theme_colors()
    check_eq("load_theme_colors: bg1 (no alpha suffix)", colors["bg1"], "rgba(46, 52, 64, 1.000)")
    check_eq("load_theme_colors: bg0 (with the F2 alpha suffix)", colors["bg0"], "rgba(46, 52, 64, 0.949)")
    check_eq("load_theme_colors: bg3 (accent color)", colors["bg3"], "rgba(129, 161, 193, 0.949)")
    check_eq("load_theme_colors: fg0", colors["fg0"], "rgba(216, 222, 233, 1.000)")

    os.remove(picker_colors_path)
    check_eq(
        "load_theme_colors: falls back to DEFAULT_COLORS untouched when the file doesn't exist",
        mp.load_theme_colors(), mp.DEFAULT_COLORS,
    )
finally:
    if old_home is None:
        del os.environ["HOME"]
    else:
        os.environ["HOME"] = old_home
    shutil.rmtree(fake_home)

print()
print("=== ohmydebn-theme-carousel (pure logic) ===")
# Formerly two separate scripts/hotkeys/menu entries (this one for themes,
# ohmydebn-theme-bg-carousel for backgrounds within the current theme) -
# folded into one, and the background-carousel coverage that used to live
# in its own "=== ohmydebn-theme-bg-carousel ===" section is folded in here
# too now (list_backgrounds_for_theme/current_background_path), alongside
# new coverage for the D-pad's move()/move_background() and the bg_index
# live-symlink-seeding bug this merge surfaced and fixed.
tc = load("ohmydebn-theme-carousel")

check_eq("slug_to_display: simple hyphenated slug", tc.slug_to_display("retro-82"), "Retro 82")
check_eq("slug_to_display: multi-word slug", tc.slug_to_display("all-hallows-eve"), "All Hallows Eve")
check_eq("slug_to_display: single word", tc.slug_to_display("nord"), "Nord")

# filter_slugs: the S-search matcher - case-insensitive substring against
# BOTH the raw slug and its display form, so "tokyo night" (space) and
# "tokyo-night" (hyphen) both hit the same theme.
SLUGS = ["matte-black", "pitch-black", "tokyo-night", "nord"]
check_eq("filter_slugs: plain substring", tc.filter_slugs("tok", SLUGS), ["tokyo-night"])
check_eq("filter_slugs: case-insensitive", tc.filter_slugs("TOKYO", SLUGS), ["tokyo-night"])
check_eq("filter_slugs: spaced query matches the display form", tc.filter_slugs("tokyo night", SLUGS), ["tokyo-night"])
check_eq("filter_slugs: hyphenated query matches the raw slug", tc.filter_slugs("tokyo-night", SLUGS), ["tokyo-night"])
check_eq("filter_slugs: empty needle matches everything", tc.filter_slugs("", SLUGS), SLUGS)
check_eq("filter_slugs: no match", tc.filter_slugs("zzz", SLUGS), [])
check_eq(
    "filter_slugs: multiple matches keep list order (the search jump takes the first)",
    tc.filter_slugs("black", SLUGS),
    ["matte-black", "pitch-black"],
)

fixture = tempfile.mkdtemp(prefix="ohmydebn-test-")
try:
    user_dir = os.path.join(fixture, "user-themes")
    system_dir = os.path.join(fixture, "system-themes")
    os.makedirs(os.path.join(user_dir, "zeta", "backgrounds"))
    os.makedirs(os.path.join(user_dir, "alpha", "backgrounds"))
    os.makedirs(os.path.join(system_dir, "middle", "backgrounds"))
    # "zeta" exists in both dirs - the user copy must win, matching
    # ohmydebn-theme-set's own user-overrides-system resolution order.
    os.makedirs(os.path.join(system_dir, "zeta", "backgrounds"))

    open(os.path.join(user_dir, "zeta", "preview.png"), "w").close()
    open(os.path.join(user_dir, "zeta", "backgrounds", "2-b.jpg"), "w").close()
    open(os.path.join(user_dir, "zeta", "backgrounds", "1-a.jpg"), "w").close()
    # "alpha" has no preview.png - must fall back to its first background.
    open(os.path.join(user_dir, "alpha", "backgrounds", "only.png"), "w").close()
    # "middle" (system-only) has neither preview nor any background image.

    tc.USER_THEMES_DIR = user_dir
    tc.SYSTEM_THEMES_DIR = system_dir

    slugs = tc.list_theme_slugs()
    check_eq("list_theme_slugs: sorted, deduped across user/system", slugs, ["alpha", "middle", "zeta"])

    check_eq(
        "theme_dir: user theme takes precedence over a system theme of the same slug",
        tc.theme_dir("zeta"), os.path.join(user_dir, "zeta"),
    )
    check_eq(
        "theme_dir: falls back to the system dir when no user copy exists",
        tc.theme_dir("middle"), os.path.join(system_dir, "middle"),
    )

    check_eq(
        "first_background: sorted, picks the first by name",
        tc.first_background("zeta"), os.path.join(user_dir, "zeta", "backgrounds", "1-a.jpg"),
    )
    check("first_background: None when the dir has no images", tc.first_background("middle") is None)

    check_eq(
        "preview_image: uses preview.png when present",
        tc.preview_image("zeta"), os.path.join(user_dir, "zeta", "preview.png"),
    )
    check_eq(
        "preview_image: falls back to the first background when no preview.png exists",
        tc.preview_image("alpha"), os.path.join(user_dir, "alpha", "backgrounds", "only.png"),
    )
    check(
        "preview_image: None when neither preview.png nor any background exists",
        tc.preview_image("middle") is None,
    )

    # list_backgrounds_for_theme() deliberately has no extension filter
    # (matching ohmydebn-theme-bg-next's own `find ... -type f`, so index N
    # here means the same file `ohmydebn-theme-set --background N` would
    # pick), unlike first_background() above - a stray non-image file is
    # expected to show up too, not get silently filtered out.
    open(os.path.join(user_dir, "zeta", "backgrounds", "0-not-an-image.txt"), "w").close()
    backgrounds = tc.list_backgrounds_for_theme("zeta")
    check_eq(
        "list_backgrounds_for_theme: sorted, no extension filter (matches ohmydebn-theme-bg-next)",
        [os.path.basename(p) for p in backgrounds],
        ["0-not-an-image.txt", "1-a.jpg", "2-b.jpg"],
    )
    check_eq("list_backgrounds_for_theme: [] for a theme with no backgrounds dir contents", tc.list_backgrounds_for_theme("middle"), [])

    tc.CURRENT_THEME_FILE = os.path.join(fixture, "theme.name")
    with open(tc.CURRENT_THEME_FILE, "w", encoding="utf-8") as f:
        f.write("zeta\n")
    check_eq("current_theme_slug: reads and strips the theme name file", tc.current_theme_slug(), "zeta")
    os.remove(tc.CURRENT_THEME_FILE)
    check("current_theme_slug: None when the file doesn't exist yet (fresh install)", tc.current_theme_slug() is None)

    tc.CURRENT_BACKGROUND_LINK = os.path.join(fixture, "current-background")
    os.symlink(os.path.join(user_dir, "zeta", "backgrounds", "2-b.jpg"), tc.CURRENT_BACKGROUND_LINK)
    check_eq(
        "current_background_path: resolves the real symlink target",
        tc.current_background_path(), os.path.join(user_dir, "zeta", "backgrounds", "2-b.jpg"),
    )
    os.remove(tc.CURRENT_BACKGROUND_LINK)
    check("current_background_path: None when no symlink exists yet", tc.current_background_path() is None)

    wide_src = os.path.join(fixture, "wide.png")
    tc.GdkPixbuf.Pixbuf.new(tc.GdkPixbuf.Colorspace.RGB, False, 8, 400, 100).savev(wide_src, "png", [], [])
    cover = tc.load_cover_pixbuf(wide_src, 200, 150)
    check_eq(
        "load_cover_pixbuf: crops to exactly the requested size",
        (cover.get_width(), cover.get_height()), (200, 150),
    )

    check_eq("_hex_to_rgb: basic conversion", tc._hex_to_rgb("#e68e0d"), (230, 142, 13))
    check(
        "_relative_luminance: white is brighter than black",
        tc._relative_luminance((255, 255, 255)) > tc._relative_luminance((0, 0, 0)),
    )
    check_eq(
        "_ensure_visible: a color already above the floor is returned unchanged",
        tc._ensure_visible("#e68e0d"), "#e68e0d",
    )
    check(
        "_ensure_visible: a too-dark color gets brightened until it clears the luminance floor",
        tc._relative_luminance(tc._hex_to_rgb(tc._ensure_visible("#050505"))) >= tc.ACCENT_LUMINANCE_FLOOR,
    )
    check_eq("_rgba: formats a hex color with the given alpha", tc._rgba("#e68e0d", 0.92), "rgba(230, 142, 13, 0.92)")

    with open(os.path.join(user_dir, "zeta", "colors.toml"), "w", encoding="utf-8") as f:
        f.write('mode = "dark"\naccent = "#e68e0d"\nbackground = "#121212"\n')
    check_eq(
        "theme_accent_color: reads the accent key straight from the theme's own colors.toml",
        tc.theme_accent_color("zeta"), "#e68e0d",
    )

    # "alpha" has a colors.toml with no accent key at all - must fall back
    # rather than crash on the missing key.
    with open(os.path.join(user_dir, "alpha", "colors.toml"), "w", encoding="utf-8") as f:
        f.write('mode = "dark"\nbackground = "#121212"\n')
    check_eq(
        "theme_accent_color: falls back to DEFAULT_ACCENT when colors.toml has no accent key",
        tc.theme_accent_color("alpha"), tc.DEFAULT_ACCENT,
    )

    # "middle" has no colors.toml at all (system-only fixture theme from
    # above) - same fallback, not a crash.
    check_eq(
        "theme_accent_color: falls back to DEFAULT_ACCENT when the theme has no colors.toml",
        tc.theme_accent_color("middle"), tc.DEFAULT_ACCENT,
    )

    os.makedirs(os.path.join(user_dir, "dark-accent"))
    with open(os.path.join(user_dir, "dark-accent", "colors.toml"), "w", encoding="utf-8") as f:
        f.write('mode = "dark"\naccent = "#050505"\n')
    dark_accent_result = tc.theme_accent_color("dark-accent")
    check(
        "theme_accent_color: a real theme with an unusually dark accent gets brightened, not left illegible",
        dark_accent_result != "#050505"
        and tc._relative_luminance(tc._hex_to_rgb(dark_accent_result)) >= tc.ACCENT_LUMINANCE_FLOOR,
    )

    os.makedirs(os.path.join(user_dir, "malformed-accent"))
    with open(os.path.join(user_dir, "malformed-accent", "colors.toml"), "w", encoding="utf-8") as f:
        f.write('mode = "dark"\naccent = "not-a-hex-color"\n')
    check_eq(
        "theme_accent_color: falls back to DEFAULT_ACCENT when accent isn't a valid #rrggbb string",
        tc.theme_accent_color("malformed-accent"), tc.DEFAULT_ACCENT,
    )
finally:
    shutil.rmtree(fixture)

check_eq(
    "BROWSE_THEMES_URL is the bjarneo.github.io gallery",
    tc.BROWSE_THEMES_URL, "https://bjarneo.github.io/omarchy-themes/",
)
# R - Remove is a real chip button now (built in Carousel.__init__, toggled
# via set_sensitive()/CSS rather than conditionally-present markup - see
# make_nav_button()), not part of this markup string at all any more, so
# there's no more True/False "is it removable" variant to test here -
# build_shortcuts_markup() always returns the same three-line S/B/C markup.
shortcuts_markup = tc.build_shortcuts_markup()
check(
    "build_shortcuts_markup: name comes before the shortcut letter (matches Cancel/Apply/Remove's ordering)",
    "Search Themes - S" in shortcuts_markup
    and "Browse More Themes - B" in shortcuts_markup
    and "Create new Theme using Aether - C" in shortcuts_markup,
)
check(
    "build_shortcuts_markup: links each action to the right href",
    tc.SEARCH_THEMES_ACTION in shortcuts_markup
    and tc.BROWSE_THEMES_URL in shortcuts_markup
    and tc.CREATE_THEME_ACTION in shortcuts_markup,
)
check(
    "build_shortcuts_markup: Search (stays in-carousel) is listed above Browse/Create (both exit)",
    shortcuts_markup.index("Search") < shortcuts_markup.index("Browse") < shortcuts_markup.index("Create"),
)
check(
    "build_shortcuts_markup: Remove is not part of this markup at all (it's its own button - see REMOVE_THEME_MARKUP's absence)",
    not hasattr(tc, "REMOVE_THEME_ACTION") and "Remove" not in shortcuts_markup,
)

fixture3 = tempfile.mkdtemp(prefix="ohmydebn-test-")
original_user_themes_dir = tc.USER_THEMES_DIR
try:
    os.makedirs(os.path.join(fixture3, "user-only-theme"))
    tc.USER_THEMES_DIR = fixture3
    check("is_theme_removable: True for a theme that exists under USER_THEMES_DIR", tc.is_theme_removable("user-only-theme"))
    check(
        "is_theme_removable: False for a theme that doesn't exist there (e.g. a system-only theme)",
        not tc.is_theme_removable("some-system-only-theme"),
    )
finally:
    tc.USER_THEMES_DIR = original_user_themes_dir
    shutil.rmtree(fixture3)


class _MoveHarness:
    """Exercises the real Carousel.move()/move_background() index math
    against a stub that only has the attributes those two methods actually
    touch, plus call-counting stand-ins for the two methods move() itself
    calls as side effects (_load_backgrounds(), render()) - move_background()
    only calls render(), never _load_backgrounds(), since changing which
    background is previewed within the *same* theme never needs a fresh
    backgrounds list."""

    def __init__(self, slugs, index, backgrounds=None, bg_index=0):
        self.slugs = slugs
        self.index = index
        self.backgrounds = backgrounds or []
        self.bg_index = bg_index
        self.load_backgrounds_calls = 0
        self.render_calls = 0

    def _load_backgrounds(self):
        self.load_backgrounds_calls += 1

    def render(self):
        self.render_calls += 1


mh = _MoveHarness(["a", "b", "c"], 2)
tc.Carousel.move(mh, 1)
check_eq("move: wraps forward past the last theme index", mh.index, 0)
check_eq(
    "move: calls _load_backgrounds and render as side effects",
    (mh.load_backgrounds_calls, mh.render_calls), (1, 1),
)

mh2 = _MoveHarness(["a", "b", "c"], 0)
tc.Carousel.move(mh2, -1)
check_eq("move: wraps backward past the first theme index", mh2.index, 2)

empty_mh = _MoveHarness([], 0)
tc.Carousel.move(empty_mh, 1)
check_eq(
    "move: no-op (not a ZeroDivisionError crash) when there are no themes at all",
    (empty_mh.index, empty_mh.render_calls), (0, 0),
)

bmh = _MoveHarness(["a"], 0, backgrounds=["x.jpg", "y.jpg", "z.jpg"], bg_index=2)
tc.Carousel.move_background(bmh, 1)
check_eq("move_background: wraps forward past the last background", bmh.bg_index, 0)
check_eq(
    "move_background: calls render but not _load_backgrounds (same theme, no reason to re-scan it)",
    (bmh.render_calls, bmh.load_backgrounds_calls), (1, 0),
)

single_bmh = _MoveHarness(["a"], 0, backgrounds=["only.jpg"], bg_index=0)
tc.Carousel.move_background(single_bmh, 1)
check_eq(
    "move_background: no-op with only one background to choose between",
    (single_bmh.bg_index, single_bmh.render_calls), (0, 0),
)

zero_bmh = _MoveHarness(["a"], 0, backgrounds=[], bg_index=0)
tc.Carousel.move_background(zero_bmh, -1)
check_eq("move_background: no-op with zero backgrounds", (zero_bmh.bg_index, zero_bmh.render_calls), (0, 0))


class _BgLoadHarness:
    """Exercises the real Carousel._load_backgrounds() - just the plain
    attributes it reads/writes, no Gtk involved."""

    def __init__(self, slugs, index):
        self.slugs = slugs
        self.index = index
        self.backgrounds = []
        self.bg_index = 0


fixture5 = tempfile.mkdtemp(prefix="ohmydebn-test-")
original_user_themes_dir2 = tc.USER_THEMES_DIR
original_current_theme_slug = tc.current_theme_slug
original_current_background_path = tc.current_background_path
try:
    # Deliberately implausible slug - list_backgrounds_for_theme() also
    # checks a ~/.config/ohmydebn/backgrounds/<slug> user-override dir
    # built from this value, on the *real* HOME, not redirectable via
    # USER_THEMES_DIR - so this only stays hermetic (and immune to
    # picking up this machine's real installed themes) if the name can't
    # collide with anything real.
    slug = "ohmydebn-test-fixture-theme-9f3c1a"
    tc.USER_THEMES_DIR = fixture5
    bg_dir = os.path.join(fixture5, slug, "backgrounds")
    os.makedirs(bg_dir)
    for name in ("1-a.jpg", "2-b.jpg", "3-c.jpg"):
        open(os.path.join(bg_dir, name), "w").close()

    tc.current_theme_slug = lambda: slug
    harness = _BgLoadHarness([slug], 0)

    # The regression this whole merge surfaced and fixed: the live
    # background symlink resolves into ~/.config/ohmydebn/current/theme/
    # backgrounds/ (a `cp -r` copy ohmydebn-theme-set makes), a different
    # path string than list_backgrounds_for_theme()'s own theme_dir()-based
    # paths, for the exact same file by name. An exact-path comparison
    # here previously matched nothing for any non-override background,
    # leaving bg_index silently stuck at 0 regardless of what was actually
    # live - so pressing Enter with no navigation at all would silently
    # revert the desktop to background #1. Matching by filename instead
    # of full path is the fix under test here.
    tc.current_background_path = lambda: "/completely/different/directory/2-b.jpg"
    tc.Carousel._load_backgrounds(harness)
    check_eq(
        "_load_backgrounds: seeds bg_index by filename match across different directories (the real bug's regression test)",
        harness.bg_index, 1,
    )

    tc.current_background_path = lambda: os.path.join(bg_dir, "3-c.jpg")
    tc.Carousel._load_backgrounds(harness)
    check_eq("_load_backgrounds: seeds bg_index correctly for an exact-path match too", harness.bg_index, 2)

    tc.current_background_path = lambda: "/nowhere/orphaned.jpg"
    tc.Carousel._load_backgrounds(harness)
    check_eq("_load_backgrounds: falls back to 0 when the live filename isn't found anywhere in the list", harness.bg_index, 0)

    tc.current_theme_slug = lambda: "some-other-theme-entirely"
    tc.current_background_path = lambda: os.path.join(bg_dir, "3-c.jpg")
    tc.Carousel._load_backgrounds(harness)
    check_eq(
        "_load_backgrounds: doesn't seed from the live background when browsing a theme that isn't the live one",
        harness.bg_index, 0,
    )

    empty_harness = _BgLoadHarness([], 0)
    tc.Carousel._load_backgrounds(empty_harness)
    check_eq(
        "_load_backgrounds: empty backgrounds/bg_index (not a crash) when there are no themes at all",
        (empty_harness.backgrounds, empty_harness.bg_index), ([], 0),
    )
finally:
    tc.USER_THEMES_DIR = original_user_themes_dir2
    tc.current_theme_slug = original_current_theme_slug
    tc.current_background_path = original_current_background_path
    shutil.rmtree(fixture5)


class _RecordingProvider(tc.Gtk.CssProvider):
    """Captures every CSS payload _apply_accent() generates, so tests can
    assert on the rules themselves, not just the cache."""

    def __init__(self):
        super().__init__()
        self.payloads = []

    def load_from_data(self, data):
        self.payloads.append(data.decode("utf-8"))
        super().load_from_data(data)


class _AccentHarness:
    """Exercises the real Carousel._apply_accent() - just the CSS provider
    and cache dict it touches, no full Carousel/window needed."""

    def __init__(self):
        self._accent_provider = _RecordingProvider()
        self._accent_cache = {}


fixture6 = tempfile.mkdtemp(prefix="ohmydebn-test-")
original_user_themes_dir3 = tc.USER_THEMES_DIR
try:
    tc.USER_THEMES_DIR = fixture6
    os.makedirs(os.path.join(fixture6, "accented"))
    with open(os.path.join(fixture6, "accented", "colors.toml"), "w", encoding="utf-8") as f:
        f.write('mode = "dark"\naccent = "#e68e0d"\n')

    harness = _AccentHarness()
    tc.Carousel._apply_accent(harness, "accented")
    check_eq(
        "_apply_accent: caches the resolved accent color for the slug it was called with",
        harness._accent_cache.get("accented"), "#e68e0d",
    )
    # e68e0d is rgb(230, 142, 13) - the scrim panel joins the accent
    # system (card/side/search borders were already there).
    accent_css = harness._accent_provider.payloads[0]
    check(
        "_apply_accent: caption panel border is recolored with the accent",
        "#carousel-caption" in accent_css and "rgba(230, 142, 13, 0.92)" in accent_css,
    )

    # Second call for the same slug must not re-read colors.toml - delete
    # the theme dir entirely and confirm the cached value is still served.
    shutil.rmtree(os.path.join(fixture6, "accented"))
    tc.Carousel._apply_accent(harness, "accented")
    check_eq(
        "_apply_accent: a second call for the same slug is served from the cache, not re-read from disk",
        harness._accent_cache.get("accented"), "#e68e0d",
    )
finally:
    tc.USER_THEMES_DIR = original_user_themes_dir3
    shutil.rmtree(fixture6)


class _FakeEvent:
    def __init__(self, keyval):
        self.keyval = keyval


class _FakeLabel:
    def __init__(self):
        self.text = None

    def set_text(self, text):
        self.text = text


class _FakeStyleContext:
    def __init__(self):
        self.classes = set()

    def add_class(self, name):
        self.classes.add(name)

    def remove_class(self, name):
        self.classes.discard(name)


class _FakeSearchEntry:
    """The two pieces of Gtk.SearchEntry the real search methods touch:
    text storage (get_text/set_text - set_text deliberately does NOT
    re-emit search-changed the way GTK does; tests that want the signal
    call on_search_changed explicitly, mirroring the real sequence) and
    grab_focus()."""

    def __init__(self):
        self.text = ""
        self.focus_calls = 0
        self.visible = False

    def get_text(self):
        return self.text

    def set_text(self, text):
        self.text = text

    def show(self):
        # Real open_search() shows the entry explicitly - plain show() on
        # the bar alone left the entry invisible in the live GTK run (see
        # open_search's own comment), so the fake tracks it separately
        # rather than letting the bar's visibility speak for it.
        self.visible = True

    def grab_focus(self):
        self.focus_calls += 1


class _FakeSearchBar:
    def __init__(self):
        self.visible = False

    def show(self):
        self.visible = True

    def hide(self):
        self.visible = False


class _FakeRemoveButton:
    def __init__(self):
        self._ctx = _FakeStyleContext()

    def get_style_context(self):
        return self._ctx

    def queue_resize(self):
        pass


class _FakeCarousel(tc.Carousel):
    """Exercises Carousel.on_key_press() against a stub that skips
    Carousel.__init__() entirely, rather than a real Gtk.Window - confirmed
    by hand that this needs no live X display at all (Gdk.keyval_to_lower
    and the keyval constants themselves don't touch one), unlike
    constructing a real Carousel(), which does (get_monitor_geometry()
    needs Gdk.Display.get_default()). _arm_remove()/_disarm_remove()/
    _on_remove_clicked() run for real against this (not stubbed, unlike
    remove_current_theme() below) - they only ever touch remove_btn's
    style context and _remove_labels[0], both faked above, so there's no
    need to re-stub the two-step confirm dance itself."""

    def __init__(self):  # pylint: disable=super-init-not-called
        self.slugs = ["alpha", "beta"]
        self.index = 1
        self.finish_calls = []
        self.move_calls = []
        self.move_background_calls = []
        self.launch_calls = []
        self.open_browse_calls = 0
        self.remove_current_theme_calls = 0
        self._remove_armed = False
        self._remove_armed_slug = None
        self._remove_arm_timeout_id = None
        self._remove_labels = [_FakeLabel()]
        self.remove_btn = _FakeRemoveButton()
        self._search_open = False
        self.search_entry = _FakeSearchEntry()
        self.search_bar = _FakeSearchBar()

    def set_focus(self, widget):
        # Stubbed - the real Gtk.Window.set_focus() needs the genuinely
        # initialized Gtk.Window underneath that this bare stub doesn't
        # have (same uninitialized-GObject crash as resize_children
        # below). close_search() calls this to hand keyboard focus back
        # from the hidden entry to the window; nothing to assert on here,
        # it just must not crash.
        pass

    def finish(self, slug):
        self.finish_calls.append(slug)

    def move(self, delta):
        self.move_calls.append(delta)
        # Apply the move for real (with the real method's wrap-around),
        # not just record it - a search jump followed by Enter must apply
        # the theme the search LANDED on, which only happens if index
        # actually tracks. Every existing assertion here only checks
        # move_calls' contents, never index-after-move, so this changes
        # nothing for them.
        self.index = (self.index + delta) % len(self.slugs)

    def move_background(self, delta):
        self.move_background_calls.append(delta)

    def resize_children(self):
        # Stubbed - the real Gtk.Container.resize_children() (called by
        # _arm_remove()/_disarm_remove() via _resize_after_relabel())
        # needs a genuinely initialized GObject underneath, which this
        # bare stub (skips Carousel.__init__(), so Gtk.Window.__init__()
        # never runs either) confirmed by hand does not have - crashes
        # with "object ... is not initialized" otherwise.
        pass

    def launch_and_close(self, argv):
        self.launch_calls.append(argv)

    def open_browse_themes(self):
        # Stubbed - the real implementation calls
        # Gtk.show_uri_on_window(), which needs a live display this bare
        # stub (which skips Carousel.__init__() entirely) never has.
        # open_aether() needs no such stub - it's a thin wrapper straight
        # to the already-stubbed launch_and_close(), inherited unmodified.
        self.open_browse_calls += 1

    def remove_current_theme(self):
        # Stubbed - the real implementation does a real subprocess.run()
        # against ohmydebn-theme-remove plus a real list_theme_slugs()/
        # render() refresh, all verified by hand against a real disposable
        # theme instead (confirmed the directory actually gets deleted,
        # the slug list shrinks by exactly one, and the index lands on a
        # valid next theme) - _on_remove_clicked()'s job is just deciding
        # *whether* (and when, given the two-step confirm) to call this at
        # all, which is what's tested here.
        self.remove_current_theme_calls += 1


def press(fake, keyval):
    return tc.Carousel.on_key_press(fake, None, _FakeEvent(keyval))


# Regression coverage for the shortcut-key routing specifically - this
# exact mapping (which key launches which theme action) has been hand-
# verified after each of several rounds of relabeling/remapping in this
# project's history; a single wrong Gdk.KEY_x here would silently
# misroute a shortcut with no error, which is exactly the kind of typo
# this guards against permanently instead of relying on re-checking by
# hand every time it's touched again.
fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_Escape)
check_eq("on_key_press: Escape cancels (finish(None))", fake.finish_calls, [None])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_Return)
check_eq("on_key_press: Enter applies the currently-selected slug", fake.finish_calls, ["beta"])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_Left)
press(fake, tc.Gdk.KEY_Right)
check_eq("on_key_press: Left/Right move themes back/forward, via move()", fake.move_calls, [-1, 1])
check_eq("on_key_press: Left/Right never touch move_background", fake.move_background_calls, [])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_Up)
press(fake, tc.Gdk.KEY_Down)
check_eq(
    "on_key_press: Up/Down move backgrounds back/forward, via move_background() - no longer aliases of Left/Right",
    fake.move_background_calls, [-1, 1],
)
check_eq("on_key_press: Up/Down never touch move (the theme list)", fake.move_calls, [])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_b)
press(fake, tc.Gdk.KEY_B)
check_eq("on_key_press: b/B (case-insensitive) opens Browse More Themes", fake.open_browse_calls, 2)
check_eq("on_key_press: b/B does not also launch anything directly", fake.launch_calls, [])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_c)
press(fake, tc.Gdk.KEY_C)
check_eq(
    "on_key_press: c/C (case-insensitive) launches Aether, not Browse",
    fake.launch_calls, [["/usr/share/aether/aether"]] * 2,
)
check_eq("on_key_press: c/C does not also open Browse", fake.open_browse_calls, 0)

# R only acts when the currently-selected slug is removable (see
# is_theme_removable()) - stubbing that module-level function directly
# here, rather than the fake slugs needing to correspond to real
# directories anywhere, keeps this test isolated from the real filesystem.
# R is a two-step confirm (see _arm_remove()/_on_remove_clicked()): the
# first press only arms it, the second (for the same slug) actually
# removes - added after a "should Remove theme have a confirm prompt?"
# question, since a single keypress in a full-screen view with no undo
# was the one place this carousel broke its own "nothing touches real
# state without deliberate confirmation" rule everywhere else.
_real_is_theme_removable = tc.is_theme_removable
try:
    tc.is_theme_removable = lambda slug: True
    fake = _FakeCarousel()
    handled = press(fake, tc.Gdk.KEY_r)
    check_eq("on_key_press: first r arms rather than removing immediately", fake.remove_current_theme_calls, 0)
    check_eq("on_key_press: first r reports itself handled", handled, True)
    check("on_key_press: first r relabels the button to the armed prompt", fake._remove_labels[0].text == tc.REMOVE_LABEL_ARMED)
    check(
        "on_key_press: first r adds the armed CSS class",
        "carousel-action-remove-armed" in fake.remove_btn.get_style_context().classes,
    )

    handled = press(fake, tc.Gdk.KEY_r)
    check_eq("on_key_press: second r (same slug) actually removes", fake.remove_current_theme_calls, 1)
    check_eq("on_key_press: second r reports itself handled", handled, True)
    check("on_key_press: confirming removal disarms - label back to the default", fake._remove_labels[0].text == tc.REMOVE_LABEL_DEFAULT)
    check(
        "on_key_press: confirming removal disarms - armed CSS class removed",
        "carousel-action-remove-armed" not in fake.remove_btn.get_style_context().classes,
    )
    check_eq("on_key_press: confirming removal clears the armed flag", fake._remove_armed, False)

    # Arming for "beta" (index 1), then browsing to a *different* slug and
    # pressing r again must arm for the new slug, not silently remove it -
    # the exact scenario this whole feature exists to prevent.
    fake2 = _FakeCarousel()
    press(fake2, tc.Gdk.KEY_r)
    check("on_key_press: armed for the original slug", fake2._remove_armed_slug == "beta")
    fake2.index = 0  # simulates having browsed to "alpha" in between
    handled = press(fake2, tc.Gdk.KEY_r)
    check_eq(
        "on_key_press: r for a different slug arms *that* slug instead of confirming the stale one",
        fake2.remove_current_theme_calls, 0,
    )
    check_eq("on_key_press: the armed slug follows the new selection", fake2._remove_armed_slug, "alpha")

    # An armed prompt nobody responds to reverts on its own - simulated
    # directly rather than waiting out REMOVE_ARM_TIMEOUT_MS for real.
    fake3 = _FakeCarousel()
    press(fake3, tc.Gdk.KEY_r)
    check("on_key_press: armed before the simulated timeout", fake3._remove_armed)
    fake3._on_remove_arm_timeout()
    check_eq("_on_remove_arm_timeout: disarms on its own without any user action", fake3._remove_armed, False)
    check(
        "_on_remove_arm_timeout: relabels back to the default",
        fake3._remove_labels[0].text == tc.REMOVE_LABEL_DEFAULT,
    )

    # Escape while armed only backs out of the confirm prompt - it must
    # not also close the whole carousel the way a bare Escape does.
    fake4 = _FakeCarousel()
    press(fake4, tc.Gdk.KEY_r)
    handled = press(fake4, tc.Gdk.KEY_Escape)
    check_eq("on_key_press: Escape while armed disarms rather than finishing", fake4.finish_calls, [])
    check_eq("on_key_press: Escape while armed still reports itself handled", handled, True)
    check_eq("on_key_press: Escape while armed clears the armed flag", fake4._remove_armed, False)
    # A second Escape (nothing armed any more) falls through to the normal
    # cancel-the-whole-carousel behavior, same as it always has.
    press(fake4, tc.Gdk.KEY_Escape)
    check_eq("on_key_press: Escape with nothing armed still cancels normally", fake4.finish_calls, [None])

    tc.is_theme_removable = lambda slug: False
    fake = _FakeCarousel()
    handled = press(fake, tc.Gdk.KEY_r)
    check_eq("on_key_press: r does nothing when the current theme isn't removable", fake.remove_current_theme_calls, 0)
    check_eq("on_key_press: r (not removable) falls through unhandled", handled, False)
finally:
    tc.is_theme_removable = _real_is_theme_removable

# Regression guard: A (Install All) and U (the old inline URL-entry flow)
# were both dropped once bjarneo.github.io's own aether:// install path
# made them redundant - confirming they're genuinely unbound now, not
# just silently doing nothing while still technically "handled".
fake = _FakeCarousel()
for kv in (tc.Gdk.KEY_a, tc.Gdk.KEY_u):
    check_eq(
        f"on_key_press: {tc.Gdk.keyval_name(kv)} is unbound now (returns False)",
        press(fake, kv), False,
    )
check_eq("on_key_press: A/U triggered nothing", fake.launch_calls + [fake.open_browse_calls], [0])

fake = _FakeCarousel()
handled = press(fake, tc.Gdk.KEY_x)
check_eq("on_key_press: an unbound key is left unhandled (returns False)", handled, False)

# S-search: the box floats over the carousel and each keystroke jumps the
# carousel itself to the first match - no results list anywhere. Real
# open_search()/close_search()/on_search_changed()/on_search_key() all run
# here against the fakes above; only the actual GTK widgets are stubbed.
fake = _FakeCarousel()
handled = press(fake, tc.Gdk.KEY_s)
check_eq("on_key_press: s reports itself handled", handled, True)
check("on_key_press: s opens the search box", fake._search_open and fake.search_bar.visible)
check("on_key_press: s shows the entry itself, not just the bar", fake.search_entry.visible)
check_eq("on_key_press: s focuses the entry", fake.search_entry.focus_calls, 1)
check_eq("on_key_press: s neither moves nor applies/cancels", fake.move_calls + fake.finish_calls, [])
fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_S)
check_eq("on_key_press: S is case-insensitive (same handler as s)", fake.search_entry.focus_calls, 1)

# THE key-routing invariant while the box is open: the window-level
# handler must go completely inert. GTK3 delivers key-press-event to the
# toplevel window's handlers BEFORE the focused entry ever sees the key,
# so without the _search_open guard, typing "c" into the box launched
# Aether before the character could be inserted - the exact bug this
# regression-tests (confirmed live). Returning False is what lets the
# window's default handler forward the keystroke to the entry as text.
fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)  # opens the box
for kv in (tc.Gdk.KEY_b, tc.Gdk.KEY_c, tc.Gdk.KEY_r, tc.Gdk.KEY_s):
    handled = press(fake, kv)
    check_eq(
        f"on_key_press: {tc.Gdk.keyval_name(kv)} while searching is forwarded, not intercepted",
        handled, False,
    )
check_eq(
    "on_key_press: letters typed while searching trigger no actions at all",
    fake.launch_calls + fake.finish_calls + fake.move_calls + [fake.open_browse_calls + fake.remove_current_theme_calls],
    [0],
)
check("on_key_press: searching letters don't reopen/toggle the box", fake._search_open)
# Escape/Enter while searching are the entry handler's job, not the
# window's - the window must forward them too (Escape closes just the box
# via on_search_key, never the whole carousel).
for kv in (tc.Gdk.KEY_Escape, tc.Gdk.KEY_Return):
    check_eq(
        f"on_key_press: window forwards {tc.Gdk.keyval_name(kv)} to the entry while searching",
        press(fake, kv), False,
    )

# Closing the box releases the guard - the same letters are hotkeys again.
fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
tc.Carousel.close_search(fake)
handled = press(fake, tc.Gdk.KEY_c)
check_eq("on_key_press: c is a live Aether hotkey again after the box closes", fake.launch_calls, [["/usr/share/aether/aether"]])
check_eq("on_key_press: post-close c reports itself handled", handled, True)

# Opening search while a remove-confirm is armed disarms it - an armed
# "Confirm Remove?" left hot under the search box is exactly the stale-arm
# scenario _arm_remove() guards against.
_real_is_theme_removable2 = tc.is_theme_removable
try:
    tc.is_theme_removable = lambda slug: True
    fake = _FakeCarousel()
    press(fake, tc.Gdk.KEY_r)
    check("search: pre-condition - remove is armed before s", fake._remove_armed)
    press(fake, tc.Gdk.KEY_s)
    check_eq("on_key_press: s disarms a pending remove-confirm", fake._remove_armed, False)
    check("on_key_press: s disarm restores the default remove label", fake._remove_labels[0].text == tc.REMOVE_LABEL_DEFAULT)
finally:
    tc.is_theme_removable = _real_is_theme_removable2

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
fake.search_entry.set_text("alpha")
tc.Carousel.on_search_changed(fake, fake.search_entry)
check_eq("on_search_changed: typing jumps by move(delta) toward the first match", fake.move_calls, [-1])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
fake.search_entry.set_text("BETA")
tc.Carousel.on_search_changed(fake, fake.search_entry)
check_eq("on_search_changed: matching is case-insensitive", fake.move_calls, [0])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
fake.search_entry.set_text("zzz")
tc.Carousel.on_search_changed(fake, fake.search_entry)
check_eq("on_search_changed: no match stays put", fake.move_calls, [])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
tc.Carousel.on_search_changed(fake, fake.search_entry)  # text still ""
check_eq("on_search_changed: empty needle stays put (no jump to alphabetical first)", fake.move_calls, [])

# close_search() clears the entry text - the _search_open guard must drop
# FIRST, or that clearing would emit an empty-needle search-changed and
# jump the carousel just because the user dismissed the box. Fake's
# set_text doesn't emit the signal itself, so this drives the same
# sequence by hand: close, then the (guarded) changed signal.
fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
fake.search_entry.set_text("alpha")
tc.Carousel.on_search_changed(fake, fake.search_entry)
tc.Carousel.close_search(fake)
tc.Carousel.on_search_changed(fake, fake.search_entry)
check_eq("close_search: clearing the text afterward can't jump the carousel", fake.move_calls, [-1])
check("close_search: box hidden and marked closed", not fake._search_open and not fake.search_bar.visible)
check_eq("close_search: entry text cleared for next time", fake.search_entry.get_text(), "")
check_eq("close_search: nothing applied or cancelled", fake.finish_calls, [])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
handled = tc.Carousel.on_search_key(fake, None, _FakeEvent(tc.Gdk.KEY_Escape))
check_eq("on_search_key: Escape reports itself handled", handled, True)
check("on_search_key: Escape closes only the search box (carousel stays up)", not fake._search_open and fake.finish_calls == [])

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
fake.search_entry.set_text("alpha")
tc.Carousel.on_search_changed(fake, fake.search_entry)
fake.move_calls.clear()  # the jump itself isn't what this asserts
handled = tc.Carousel.on_search_key(fake, None, _FakeEvent(tc.Gdk.KEY_Return))
check_eq("on_search_key: Enter applies the search-landed theme directly", fake.finish_calls, ["alpha"])
check_eq("on_search_key: Enter reports itself handled", handled, True)

fake = _FakeCarousel()
press(fake, tc.Gdk.KEY_s)
handled = tc.Carousel.on_search_key(fake, None, _FakeEvent(tc.Gdk.KEY_j))
check_eq("on_search_key: ordinary keys fall through to the entry's own text handling", handled, False)
check_eq("on_search_key: fall-through keys trigger nothing", fake.move_calls + fake.finish_calls, [])

# Click routing for the caption's Search link - same fake action: URI
# pattern Create uses (see the comment above on_shortcuts_link_activated's
# Create/Browse tests below).
fake = _FakeCarousel()
handled = tc.Carousel.on_shortcuts_link_activated(fake, None, tc.SEARCH_THEMES_ACTION)
check("click Search: opens the search box", fake._search_open and fake.search_bar.visible)
check_eq("click Search: returns True (fully handled, no real URI open attempted)", handled, True)
check_eq("click Search: doesn't also close or apply anything", fake.finish_calls, [])

# Click routing for Create/Browse via on_shortcuts_link_activated() instead
# of on_key_press() - Create uses a fake action: URI (not a real web
# address) specifically so GTK's own link click-detection can be reused
# without a real URI handler ever being asked to open one. Remove used to
# be routed through here too via its own fake action: URI, back when it was
# a fake link inside shortcuts_label's markup - it's a real chip button now
# (remove_btn, wired directly to a "clicked" signal in __init__, not
# through this method at all - see REMOVE_THEME_ACTION's absence above),
# so there's no click-routing test for it here any more.
fake = _FakeCarousel()
handled = tc.Carousel.on_shortcuts_link_activated(fake, None, tc.CREATE_THEME_ACTION)
check_eq("click Create: launches Aether", fake.launch_calls, [["/usr/share/aether/aether"]])
check_eq("click Create: returns True (fully handled, no real URI open attempted)", handled, True)

fake = _FakeCarousel()
handled = tc.Carousel.on_shortcuts_link_activated(fake, None, tc.BROWSE_THEMES_URL)
check_eq(
    "click Browse (a real URL): returns False so GTK's own default handler still opens it",
    handled, False,
)
check_eq("click Browse: doesn't also call launch_and_close", fake.launch_calls, [])

print()
print("=== remove_current_theme (real method, not the _FakeCarousel stub) ===")


class _RemoveHarness:
    """Exercises the real Carousel.remove_current_theme() logic - slug
    selection, the is_theme_removable guard, the list refresh, index
    clamping, and the render() call - against real USER_THEMES_DIR
    fixtures. Everything above this point only ever calls the stubbed
    remove_current_theme() on _FakeCarousel, so none of it actually
    exercises this method's own body."""

    def __init__(self, slugs, index):
        self.slugs = slugs
        self.index = index
        self.render_calls = 0
        self.backgrounds = []
        self.bg_index = 0
        self._last_theme_index = index

    def render(self):
        self.render_calls += 1

    # The real remove_current_theme() re-scans backgrounds for whichever
    # theme ends up selected after the removal - stub it as a no-op here
    # since that path is already covered by _BgLoadHarness above.
    def _load_backgrounds(self):
        pass


fixture4 = tempfile.mkdtemp(prefix="ohmydebn-test-")
original_user_themes_dir = tc.USER_THEMES_DIR
original_subprocess_run = tc.subprocess.run
removed_argv = []


def _fake_theme_remove_run(argv, check=False):
    removed_argv.append(argv)
    shutil.rmtree(os.path.join(fixture4, argv[-1]), ignore_errors=True)


try:
    tc.USER_THEMES_DIR = fixture4
    tc.subprocess.run = _fake_theme_remove_run
    for slug in ("alpha", "beta", "gamma"):
        os.makedirs(os.path.join(fixture4, slug))

    harness = _RemoveHarness(["alpha", "beta", "gamma"], 1)  # pointing at "beta"
    tc.Carousel.remove_current_theme(harness)
    check_eq(
        "remove_current_theme: invokes ohmydebn-theme-remove with the selected slug",
        removed_argv, [[f"{tc.OHMYDEBN_BIN}/ohmydebn-theme-remove", "beta"]],
    )
    check("remove_current_theme: the removed theme's directory is actually gone", not os.path.isdir(os.path.join(fixture4, "beta")))
    check_eq("remove_current_theme: refreshes self.slugs from disk afterward", harness.slugs, ["alpha", "gamma"])
    check_eq("remove_current_theme: index stays pointed at a valid theme after the removal", harness.index, 1)
    check_eq("remove_current_theme: re-renders after removing", harness.render_calls, 1)

    removed_argv.clear()
    harness2 = _RemoveHarness(["alpha", "gamma"], 1)  # pointing at "gamma", the last one
    tc.Carousel.remove_current_theme(harness2)
    check_eq("remove_current_theme: removing the last item clamps the index down, not out of range", harness2.index, 0)
    check_eq("remove_current_theme: slugs list reflects the removal", harness2.slugs, ["alpha"])

    # Safety guard: even called directly (bypassing on_key_press's own
    # is_theme_removable check), remove_current_theme() must never touch a
    # non-removable (system) theme - the real belt-and-suspenders check,
    # not the dispatch-level one already covered above.
    removed_argv.clear()
    harness3 = _RemoveHarness(["system-theme", "alpha"], 0)  # "system-theme" has no dir under fixture4
    tc.Carousel.remove_current_theme(harness3)
    check_eq("remove_current_theme: does nothing when the selected slug isn't removable", removed_argv, [])
    check_eq("remove_current_theme: slugs list is untouched on the safety-guard path", harness3.slugs, ["system-theme", "alpha"])
    check_eq("remove_current_theme: no render() call on the safety-guard path", harness3.render_calls, 0)

    harness4 = _RemoveHarness([], 0)
    tc.Carousel.remove_current_theme(harness4)
    check_eq("remove_current_theme: no-op when there are no themes at all", removed_argv, [])
finally:
    tc.USER_THEMES_DIR = original_user_themes_dir
    tc.subprocess.run = original_subprocess_run
    shutil.rmtree(fixture4)

print("=== remove_legacy_aether_desktop_files (real function) ===")
# Same list of names as install/cleanup/local-share.sh's own cleanup loop
# (kept in sync by hand - see LEGACY_AETHER_DESKTOP_FILES's own comment);
# this one is called fresh from open_browse_themes() right before sending
# the user to a page that can fire an aether:// callback, in case aether
# re-creates either file on its own each time it runs.
fixture5 = tempfile.mkdtemp()
apps_dir = os.path.join(fixture5, ".local", "share", "applications")
os.makedirs(apps_dir)
for name in tc.LEGACY_AETHER_DESKTOP_FILES:
    open(os.path.join(apps_dir, name), "w").close()
other_desktop_file = os.path.join(apps_dir, "some-other-app.desktop")
open(other_desktop_file, "w").close()
original_home = os.environ.get("HOME")
try:
    os.environ["HOME"] = fixture5
    tc.remove_legacy_aether_desktop_files()
    for name in tc.LEGACY_AETHER_DESKTOP_FILES:
        check(f"{name} removed", not os.path.exists(os.path.join(apps_dir, name)))
    check("unrelated desktop file left alone", os.path.exists(other_desktop_file))
    # Calling it again with nothing left to remove doesn't raise.
    tc.remove_legacy_aether_desktop_files()
    check("calling again with nothing to remove doesn't raise", True)
finally:
    if original_home is None:
        os.environ.pop("HOME", None)
    else:
        os.environ["HOME"] = original_home
    shutil.rmtree(fixture5)

print()
print("=== Picker: deferred-close scheduling (--serve mode's flash/stuck-open fix) ===")


class _FakePicker(mp.Picker):
    """Exercises finish()/_schedule_close()/_deferred_close()/reload()'s
    cancellation against a stub that skips Picker.__init__() entirely -
    same technique _FakeCarousel uses above, for the same reason: a real
    Picker() needs a live X display (__init__ calls get_monitor_geometry(),
    which needs Gdk.Display.get_default() - see this module's own
    docstring). show()/set_title()/populate() are stubbed because *they*
    need a genuinely realized window/listbox underneath that this bare
    stub doesn't have - but none of that is what's under test here. The
    scheduling logic itself (_pending_close_id, _schedule_close(),
    _deferred_close(), reload()'s cancel-if-pending check) only ever
    touches plain attributes and real GLib.timeout_add()/source_remove()
    calls, which need no display at all - confirmed by hand, this whole
    class instantiates and runs with no DISPLAY set."""

    def __init__(self, on_result=None):  # pylint: disable=super-init-not-called
        self.mode = "menu"
        self._closing = False
        self._pending_close_id = None
        self.on_result = on_result
        self.entry = _FakeSearchEntry()
        self.show_calls = 0

    def show(self):
        self.show_calls += 1

    def set_title(self, _title):
        pass

    def populate(self, _rows):
        pass


_main_quit_calls = []
_real_main_quit = mp.Gtk.main_quit
mp.Gtk.main_quit = lambda: _main_quit_calls.append(1)
_leaked_pickers = []
try:
    results = []
    win = _FakePicker(on_result=results.append)
    win.finish("Install")
    check_eq("finish(value): on_result gets the value", results, ["Install"])
    check("finish(value): schedules a pending close instead of hiding/quitting immediately", win._pending_close_id is not None)
    check_eq("finish(value): doesn't quit immediately - reload() might still be a moment away", len(_main_quit_calls), 0)
    _leaked_pickers.append(win)

    # The common case: another menu() call (a submenu pick) arrives before
    # the close would fire. reload() must cancel it - this is the actual
    # flash fix, not just a hide/show optimization: the window was never
    # meant to disappear for this pick at all.
    win2 = _FakePicker(on_result=lambda v: None)
    win2.finish("Install")
    check("reload() cancels a pending close", win2._pending_close_id is not None)
    win2.reload("", "Install")
    check("reload() actually clears the pending close", win2._pending_close_id is None)
    check_eq("reload() shows the window", win2.show_calls, 1)
    check_eq("a cancelled close never fires", len(_main_quit_calls), 0)

    # No pending close (e.g. the session's first request): reload() is
    # still just a normal show, not an error on a no-op cancel.
    win3 = _FakePicker(on_result=lambda v: None)
    win3.reload("", "")
    check_eq("reload() with nothing pending still shows", win3.show_calls, 1)

    # The rare case: nothing calls reload() in time (a real leaf pick -
    # About, Demo, ... - bin/ohmydebn-menu never loops back to
    # show_main_menu, so nothing else is coming). The deferred callback
    # must actually quit the process, not just hide the window - a hidden
    # process would linger until whatever it launched closes and the
    # whole ohmydebn-menu script's own EXIT trap finally reaps it, which
    # is the exact bug this whole mechanism exists to avoid.
    win4 = _FakePicker(on_result=lambda v: None)
    win4.finish("About")
    win4._deferred_close()
    check_eq("an uncancelled close quits the process", len(_main_quit_calls), 1)
    check("an uncancelled close clears _pending_close_id", win4._pending_close_id is None)

    # Escape/click-away (empty result) schedules a close the same way -
    # many case-statement fallback arms in bin/ohmydebn-menu re-open the
    # same or parent menu on an empty result, so this needs to be just as
    # cancellable as a real pick, not hidden/quit unconditionally.
    results5 = []
    win5 = _FakePicker(on_result=results5.append)
    win5.finish(None)
    check_eq("finish(None) (escape/cancel): on_result gets empty string", results5, [""])
    check("finish(None): also schedules a pending close", win5._pending_close_id is not None)
    _leaked_pickers.append(win5)

    # _schedule_close() itself doesn't double-schedule if called twice -
    # a defensive check on the primitive, independent of finish()'s own
    # single-call-per-pick guard (_closing).
    win6 = _FakePicker(on_result=lambda v: None)
    win6._schedule_close()
    first_id = win6._pending_close_id
    win6._schedule_close()
    check_eq("_schedule_close() doesn't double-schedule", win6._pending_close_id, first_id)
    _leaked_pickers.append(win6)
finally:
    mp.Gtk.main_quit = _real_main_quit
    # win/win5/win6 above scheduled a real close and neither cancelled nor
    # fired it - nothing in this process ever runs a GLib main loop, so a
    # leaked source is harmless here either way, but leave nothing armed.
    for leaked in _leaked_pickers:
        if leaked._pending_close_id is not None:
            mp.GLib.source_remove(leaked._pending_close_id)

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(0 if TESTS_FAILED == 0 else 1)
