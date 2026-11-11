#!/usr/bin/python3
#
# Tests for bin/ohmydebn_hotkeys.py, which gathers the hotkeys Super + K
# lists. Super + K used to open the docs' hotkey page in a browser, which
# showed OhMyDebn's stock hotkeys rather than the user's own; the list now
# reads them live. gsettings is a stand-in reader, Cinnamon's keyboard
# settings module and the stock hotkey file are scratch copies, and the
# Cinnamon spices folder points into a scratch directory, so nothing here
# depends on this machine's desktop.

import json
import os
import sys
import tempfile
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
hk = SourceFileLoader("ohmydebn_hotkeys", os.path.join(REPO_ROOT, "bin", "ohmydebn_hotkeys.py")).load_module()

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
    check(desc, actual == expected)
    if actual != expected:
        print(f"      expected: {expected!r}\n      actual:   {actual!r}")


print("=== bin/ohmydebn_hotkeys.py ===")

# --- keys, written as the docs write them ---
check_eq("modifiers and a letter", hk.format_accel("<Primary><Shift>g"), "Ctrl + Shift + G")
check_eq("Super alone (the menu key)", hk.format_accel("Super_L"), "Super")
check_eq("Return is Enter", hk.format_accel("<Super>Return"), "Super + Enter")
check_eq("space", hk.format_accel("<Super><Alt>space"), "Super + Alt + Space")
check_eq("punctuation by name", hk.format_accel("<Super>comma"), "Super + ,")
check_eq("Page_Up", hk.format_accel("<Super>Page_Up"), "Super + Page Up")
check_eq("Mod4 and Mod1", hk.format_accel("<Mod4><Mod1>l"), "Super + Alt + L")
check_eq("the key above Tab, as the docs name it", hk.format_accel("<Super>Above_Tab"), "Super + the key left of 1")
check_eq("keypad", hk.format_accel("<Super>KP_1"), "Super + Keypad 1")
check_eq("keypad, by its Num Lock-off name (gTile's)", hk.format_accel("<Primary><Shift>KP_End"), "Ctrl + Shift + Keypad 1")
check_eq("keypad 9", hk.format_accel("<Primary><Shift>KP_Prior"), "Ctrl + Shift + Keypad 9")
check_eq("hardware-only key: nothing to press", hk.format_accel("XF86AudioPlay"), "")
check_eq("empty", hk.format_accel(""), "")
check_eq("several, joined with or", hk.format_accels(["<Super>R", "<Super><Alt>space"]), "Super + R or Super + Alt + Space")
check_eq("Super_L and Super_R: once", hk.format_accels(["Super_L", "Super_R"]), "Super")
check_eq("hardware keys dropped from a list", hk.format_accels(["XF86Calculator", "<Super>c"]), "Super + C")

# --- Cinnamon's keyboard settings table ---
CS_SOURCE = '''
MUFFIN_KEYBINDINGS_SCHEMA = "org.cinnamon.desktop.keybindings.wm"
CINNAMON_SCHEMA = "org.cinnamon.desktop.keybindings"
CATEGORIES = [
    [_("General"),          "general",          None,       "icon"],
    [_("Windows"),          "windows",          None,       "icon"],
    [_("Inter-monitor"),    "win-monitors",     "windows",  None],
    [_("Workspaces"),       "workspaces",       None,       "icon"],
    [_("Direct Navigation"), "ws-navi",         "workspaces", None],
]
KEYBINDINGS = [
    [_("Show desktop"), MUFFIN_KEYBINDINGS_SCHEMA, "show-desktop", "general"],
    [_("Close window"), MUFFIN_KEYBINDINGS_SCHEMA, "close", "windows"],
    [_("Move window to left monitor"), MUFFIN_KEYBINDINGS_SCHEMA, "move-to-monitor-left", "win-monitors"],
    [_("Switch to workspace 1"), MUFFIN_KEYBINDINGS_SCHEMA, "switch-to-workspace-1", "ws-navi"],
    [_("Unbound"), MUFFIN_KEYBINDINGS_SCHEMA, "unbound-key", "general"],
    [_("Looking Glass"), CINNAMON_SCHEMA, "looking-glass-keybinding", "general"],
    [_("Not a hotkey"), UNKNOWN_SCHEMA, "something", "general"],
    "not a row",
]
'''
bindings, groups = hk.parse_cs_keyboard(CS_SOURCE)
check_eq("table: labels, schemas (constants resolved), keys, categories", bindings[2],
         ("Move window to left monitor", "org.cinnamon.desktop.keybindings.wm", "move-to-monitor-left", "win-monitors"))
check("table: a row naming an unknown constant is skipped", all(b[0] != "Not a hotkey" for b in bindings))
check_eq("table: six usable rows", len(bindings), 6)
check_eq("groups: a subcategory is listed under its top category", groups["win-monitors"], "Windows")
check_eq("groups: two levels up", groups["ws-navi"], "Workspaces")
check_eq("unparseable source: nothing, not an error", hk.parse_cs_keyboard("this is not ( python"), ([], {}))

# --- loading, with a stand-in for gsettings ---


class FakeReader:
    def __init__(self, strv, customs):
        self._strv, self._customs = strv, customs

    def strv(self, schema, key):
        return self._strv.get((schema, key))

    def custom(self, slot_id):
        return self._customs.get(slot_id)


WM = "org.cinnamon.desktop.keybindings.wm"


def load(enabled_extensions=("gTile@OhMyDebn",), menu_key="Super_L::Super_R"):
    tmp = tempfile.mkdtemp()
    cs = os.path.join(tmp, "cs_keyboard.py")
    with open(cs, "w") as f:
        f.write(CS_SOURCE)
    stock = os.path.join(tmp, "keybinding-custom.txt")
    with open(stock, "w") as f:
        f.write('keybinding-custom 0 "Browser" "x" "[\'<Super>B\']" "..."\n')
        f.write('keybinding-custom 4 "Keybindings" "x" "[\'<Super>K\']" "..."\n')
        f.write('keybinding-custom 20 "OhMyDebn menu" "x" "[\'<Super>space\']" "..."\n')
    spices = os.path.join(tmp, "spices")
    os.makedirs(os.path.join(spices, "gTile@OhMyDebn"))
    os.makedirs(os.path.join(spices, "menu@cinnamon.org"))
    with open(os.path.join(spices, "gTile@OhMyDebn", "gTile@OhMyDebn.json"), "w") as f:
        json.dump({
            "hotkey": {"type": "keybinding", "value": "<Primary><Shift>g::", "description": "Global Hotkey for gTile"},
            "animation": {"type": "switch", "value": True, "description": "Not a hotkey"},
            "unset": {"type": "keybinding", "value": "", "description": "Nothing bound"},
        }, f)
    with open(os.path.join(spices, "menu@cinnamon.org", "0.json"), "w") as f:
        json.dump({"overlay-key": {"type": "keybinding", "value": menu_key}}, f)
    hk.SPICES = spices
    reader = FakeReader(
        {
            ("org.cinnamon.desktop.keybindings", "custom-list"):
                ["custom-20", "custom-0", "custom-1000", "custom0", "__dummy__", "custom-4", "custom-7"],
            ("org.cinnamon", "enabled-extensions"): list(enabled_extensions),
            (WM, "show-desktop"): ["<Super>d"],
            (WM, "close"): ["<Alt>F4", "<Super>w"],
            (WM, "move-to-monitor-left"): ["<Super><Shift>Left"],
            (WM, "switch-to-workspace-1"): ["<Super>1"],
            (WM, "unbound-key"): [],
            ("org.cinnamon.desktop.keybindings", "looking-glass-keybinding"): ["XF86Tools"],
        },
        {
            "custom-0": ("Browser", "/usr/share/ohmydebn/bin/ohmydebn-browser-tiled", ["<Super>B"]),
            "custom-4": ("Keybindings", "/usr/share/ohmydebn/bin/ohmydebn-hotkeys", ["<Super>K"]),
            "custom-20": ("OhMyDebn menu", "/usr/share/ohmydebn/bin/ohmydebn-menu", ["<Super>space"]),
            "custom-1000": ("Slack", "slack", ["<Super>S"]),
            "custom0": ("Notes", "xed", ["<Ctrl><Super>n"]),
            # A stock slot the user unbound (keybinding-unbind): nothing to press.
            "custom-7": ("btop", "btop", [""]),
        },
    )
    return hk.load_hotkeys(reader, cs_keyboard=cs, stock_file=stock)


hotkeys = load()
names = [h.name for h in hotkeys]
check_eq("order: the menu key, OhMyDebn's in slot order, the user's own, gTile, then Cinnamon's",
         names[:9], ["Cinnamon menu", "Browser", "Keybindings", "OhMyDebn menu", "Slack", "Notes",
                     "Global Hotkey for gTile", "Show desktop", "Close window"])
check_eq("groups", [h.group for h in hotkeys[:7]],
         ["OhMyDebn", "OhMyDebn", "OhMyDebn", "OhMyDebn", "Your own", "Your own", "Tiling (gTile)"])
check("an unbound stock hotkey isn't listed", "btop" not in names)
check("Cinnamon's transient __dummy__ entry isn't listed", all("dummy" not in n for n in names))
check("an unbound Cinnamon hotkey isn't listed", "Unbound" not in names)
check("a hardware-only Cinnamon hotkey isn't listed", "Looking Glass" not in names)
check("a gTile setting that isn't a hotkey isn't listed", "Not a hotkey" not in names)
check("a gTile hotkey with nothing bound isn't listed", "Nothing bound" not in names)
by_name = {h.name: h for h in hotkeys}
check_eq("Cinnamon's subcategory: listed under its top group", by_name["Move window to left monitor"].group, "Windows")
check_eq("several keys for one hotkey", by_name["Close window"].keys, "Alt + F4 or Super + W")
check_eq("custom hotkeys run their command", by_name["Slack"].command, "slack")
check("Cinnamon's own hotkeys run nothing (they act on the previous window)", by_name["Close window"].command is None)
check("gTile's run nothing either", by_name["Global Hotkey for gTile"].command is None)
check_eq("the last row opens the docs' page", (hotkeys[-1].keys, hotkeys[-1].command),
         ("", "/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://ohmydebn.org/hotkeys/"))

check("gTile turned off: its hotkeys aren't listed",
      all(h.group != "Tiling (gTile)" for h in load(enabled_extensions=())))
check("no menu key set: no menu row", all(h.name != "Cinnamon menu" for h in load(menu_key="")))

# --- search ---
check("search: by name", hk.matches(by_name["Slack"], "slack"))
check("search: every word, anywhere", hk.matches(by_name["Move window to left monitor"], "super shift monitor"))
check("search: by group", hk.matches(by_name["Switch to workspace 1"], "workspaces"))
check("search: a word that isn't there", not hk.matches(by_name["Slack"], "super browser"))

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
