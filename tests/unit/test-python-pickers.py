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
# with no display at all, so the cover-fit/contain-fit math is covered.

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
tc = load("ohmydebn-theme-carousel")

check_eq("slug_to_display: simple hyphenated slug", tc.slug_to_display("retro-82"), "Retro 82")
check_eq("slug_to_display: multi-word slug", tc.slug_to_display("all-hallows-eve"), "All Hallows Eve")
check_eq("slug_to_display: single word", tc.slug_to_display("nord"), "Nord")

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

    tc.CURRENT_THEME_FILE = os.path.join(fixture, "theme.name")
    with open(tc.CURRENT_THEME_FILE, "w", encoding="utf-8") as f:
        f.write("zeta\n")
    check_eq("current_theme_slug: reads and strips the theme name file", tc.current_theme_slug(), "zeta")
    os.remove(tc.CURRENT_THEME_FILE)
    check("current_theme_slug: None when the file doesn't exist yet (fresh install)", tc.current_theme_slug() is None)

    wide_src = os.path.join(fixture, "wide.png")
    tc.GdkPixbuf.Pixbuf.new(tc.GdkPixbuf.Colorspace.RGB, False, 8, 400, 100).savev(wide_src, "png", [], [])
    cover = tc.load_cover_pixbuf(wide_src, 200, 150)
    check_eq(
        "load_cover_pixbuf: crops to exactly the requested size",
        (cover.get_width(), cover.get_height()), (200, 150),
    )

    contain = tc.load_contain_pixbuf(wide_src, 100, 100)
    check(
        "load_contain_pixbuf: fits within bounds without exceeding either dimension",
        contain.get_width() <= 100 and contain.get_height() <= 100,
    )
    check(
        "load_contain_pixbuf: preserves aspect ratio (a wide source stays wider than tall)",
        contain.get_width() > contain.get_height(),
    )
finally:
    shutil.rmtree(fixture)

check_eq(
    "BROWSE_THEMES_URL is the bjarneo.github.io gallery",
    tc.BROWSE_THEMES_URL, "https://bjarneo.github.io/omarchy-themes/",
)
removable_markup = tc.build_shortcuts_markup(True)
not_removable_markup = tc.build_shortcuts_markup(False)
check(
    "build_shortcuts_markup(True): mentions all three shortcut letters, hyphenated",
    all(f"{c} - " in removable_markup for c in "BCR"),
)
check(
    "build_shortcuts_markup(True): links each action to the right href (real URL for Browse, fake action: scheme for Create/Remove)",
    tc.BROWSE_THEMES_URL in removable_markup
    and tc.CREATE_THEME_ACTION in removable_markup
    and tc.REMOVE_THEME_ACTION in removable_markup,
)
check(
    "build_shortcuts_markup(False): Remove is omitted entirely, not just unlinked",
    "Remove" not in not_removable_markup and tc.REMOVE_THEME_ACTION not in not_removable_markup,
)
check(
    "build_shortcuts_markup(False): Browse/Create are still present",
    tc.BROWSE_THEMES_URL in not_removable_markup and tc.CREATE_THEME_ACTION in not_removable_markup,
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

check_eq(
    "_terminal_wrapped: show-logo/action/show-done, in order",
    tc.Carousel._terminal_wrapped("/some/action"),
    [
        f"{tc.OHMYDEBN_BIN}/ohmydebn-terminal", "--class", "OhMyDebn", "-e", "bash", "-c",
        f"{tc.OHMYDEBN_BIN}/ohmydebn-show-logo; /some/action; {tc.OHMYDEBN_BIN}/ohmydebn-show-done",
    ],
)


class _FakeEvent:
    def __init__(self, keyval):
        self.keyval = keyval


class _FakeCarousel(tc.Carousel):
    """Exercises Carousel.on_key_press() (and, via inheritance, the real
    _terminal_wrapped()) against a stub that skips Carousel.__init__()
    entirely, rather than a real Gtk.Window - confirmed by hand that this
    needs no live X display at all (Gdk.keyval_to_lower and the keyval
    constants themselves don't touch one), unlike constructing a real
    Carousel(), which does (get_monitor_geometry() needs
    Gdk.Display.get_default())."""

    def __init__(self):  # pylint: disable=super-init-not-called
        self.slugs = ["alpha", "beta"]
        self.index = 1
        self.finish_calls = []
        self.move_calls = []
        self.launch_calls = []
        self.open_browse_calls = 0
        self.remove_current_theme_calls = 0

    def finish(self, slug):
        self.finish_calls.append(slug)

    def move(self, delta):
        self.move_calls.append(delta)

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
        # valid next theme) - on_key_press()'s job is just deciding
        # *whether* to call this at all, which is what's tested here.
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
press(fake, tc.Gdk.KEY_Up)
press(fake, tc.Gdk.KEY_Right)
press(fake, tc.Gdk.KEY_Down)
check_eq("on_key_press: Left/Up move back, Right/Down move forward", fake.move_calls, [-1, -1, 1, 1])

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
_real_is_theme_removable = tc.is_theme_removable
try:
    tc.is_theme_removable = lambda slug: True
    fake = _FakeCarousel()
    handled = press(fake, tc.Gdk.KEY_r)
    check_eq("on_key_press: r removes the current theme when it's removable", fake.remove_current_theme_calls, 1)
    check_eq("on_key_press: r (removable) reports itself handled", handled, True)

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

# Click routing for the same three actions, via on_shortcuts_link_activated()
# instead of on_key_press() - Create/Remove use fake action: URIs (not real
# web addresses) specifically so GTK's own link click-detection can be
# reused without a real URI handler ever being asked to open one.
fake = _FakeCarousel()
handled = tc.Carousel.on_shortcuts_link_activated(fake, None, tc.CREATE_THEME_ACTION)
check_eq("click Create: launches Aether", fake.launch_calls, [["/usr/share/aether/aether"]])
check_eq("click Create: returns True (fully handled, no real URI open attempted)", handled, True)

fake = _FakeCarousel()
handled = tc.Carousel.on_shortcuts_link_activated(fake, None, tc.REMOVE_THEME_ACTION)
check_eq("click Remove: removes the current theme directly (no terminal spawn)", fake.remove_current_theme_calls, 1)
check_eq("click Remove: doesn't also spawn a terminal via launch_and_close", fake.launch_calls, [])
check_eq("click Remove: returns True", handled, True)

fake = _FakeCarousel()
handled = tc.Carousel.on_shortcuts_link_activated(fake, None, tc.BROWSE_THEMES_URL)
check_eq(
    "click Browse (a real URL): returns False so GTK's own default handler still opens it",
    handled, False,
)
check_eq("click Browse: doesn't also call launch_and_close", fake.launch_calls, [])

print()
print("=== ohmydebn-theme-bg-carousel (pure logic) ===")
bc = load("ohmydebn-theme-bg-carousel")

fixture2 = tempfile.mkdtemp(prefix="ohmydebn-test-")
try:
    bg_dir = os.path.join(fixture2, "backgrounds")
    os.makedirs(bg_dir)
    open(os.path.join(bg_dir, "2-second.jpg"), "w").close()
    open(os.path.join(bg_dir, "1-first.jpg"), "w").close()
    # ohmydebn-theme-bg-next's own `find ... -type f` has no extension
    # filter either (every real theme's backgrounds/ only ever holds
    # images in practice, so this has never mattered) - list_backgrounds()
    # deliberately matches that rather than adding filtering the original
    # script doesn't have, so this stray non-image file is expected to
    # show up too.
    open(os.path.join(bg_dir, "0-not-an-image.txt"), "w").close()

    bc.THEME_BACKGROUNDS_DIR = bg_dir
    bc.THEME_NAME_FILE = os.path.join(fixture2, "theme.name")
    with open(bc.THEME_NAME_FILE, "w", encoding="utf-8") as f:
        # Deliberately implausible name - list_backgrounds() also checks a
        # ~/.config/ohmydebn/backgrounds/<theme> user-override dir built
        # from this value, and that path isn't redirectable into the
        # fixture the way THEME_BACKGROUNDS_DIR is (it's computed inside
        # the function, not a module constant) - so this only stays
        # hermetic if the name can't collide with anything real.
        f.write("ohmydebn-test-fixture-theme-name-9f3c1a\n")

    backgrounds = bc.list_backgrounds()
    check_eq(
        "list_backgrounds: sorted, and matches ohmydebn-theme-bg-next's own no-extension-filter behavior",
        [os.path.basename(p) for p in backgrounds], ["0-not-an-image.txt", "1-first.jpg", "2-second.jpg"],
    )

    bc.CURRENT_BACKGROUND_LINK = os.path.join(fixture2, "current-link")
    os.symlink(os.path.join(bg_dir, "2-second.jpg"), bc.CURRENT_BACKGROUND_LINK)
    check_eq(
        "current_background_path: resolves the real symlink target",
        bc.current_background_path(), os.path.join(bg_dir, "2-second.jpg"),
    )
    os.remove(bc.CURRENT_BACKGROUND_LINK)
    check("current_background_path: None when no symlink exists yet", bc.current_background_path() is None)
finally:
    shutil.rmtree(fixture2)

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(0 if TESTS_FAILED == 0 else 1)
