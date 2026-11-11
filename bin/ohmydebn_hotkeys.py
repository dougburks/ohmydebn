"""The hotkeys that work on this desktop right now, for the Super + K list
(ohmydebn-menu-picker --hotkeys). Super + K used to open the docs' hotkey
page in a browser: slow, needing the network, and showing OhMyDebn's stock
hotkeys rather than this user's own. This reads them live instead:

  - Cinnamon's custom hotkeys: OhMyDebn's stock slots (custom-N, numbered as
    in install/keybinding/keybinding-custom.txt), the user's own from
    ~/.config/ohmydebn/keybindings.txt (custom-1000 and up) and any added in
    Cinnamon's keyboard settings (custom0, custom1...)
  - the Cinnamon menu's key, from the menu applet's settings
  - gTile's hotkeys, from its settings, when the extension is enabled
  - Cinnamon's own hotkeys (window management, workspaces, system...),
    labeled and grouped the way Cinnamon's keyboard settings show them

Cinnamon's labels come from the KEYBINDINGS table in its keyboard settings
module, read with ast rather than imported (importing it pulls in all of
cinnamon-settings), and translated through Cinnamon's own gettext domain,
so they match its settings in the user's language. If a later Cinnamon
changes that file, its hotkeys are still listed, under their gsettings key
names, rather than not at all.

Shortcuts inside apps (text selection, the browser, Neovim...) can't be
read from the system; the list ends with a row that opens the docs' page,
which has them."""

import ast
import gettext
import glob
import json
import os
import re
from collections import namedtuple

# keys: what to press, as the docs write it ("Super + Shift + G"); name:
# what it does; group: where it's listed; command: what Enter runs (only
# Cinnamon's custom hotkeys have one; Cinnamon's and gTile's act on the
# window that had focus before the list opened, so they just close it).
Hotkey = namedtuple("Hotkey", "keys name group command")

STOCK_FILE = "/usr/share/ohmydebn/install/keybinding/keybinding-custom.txt"
CS_KEYBOARD = "/usr/share/cinnamon/cinnamon-settings/modules/cs_keyboard.py"
SPICES = os.path.expanduser("~/.config/cinnamon/spices")
DOCS_URL = "https://ohmydebn.org/hotkeys/"
WEBAPP = "/usr/share/ohmydebn/bin/ohmydebn-launch-webapp"

KEYBINDINGS_SCHEMA = "org.cinnamon.desktop.keybindings"
CUSTOM_SCHEMA = "org.cinnamon.desktop.keybindings.custom-keybinding"
CUSTOM_PATH = "/org/cinnamon/desktop/keybindings/custom-keybindings/{}/"

GROUP_OHMYDEBN = "OhMyDebn"
GROUP_YOURS = "Your own"
GROUP_GTILE = "Tiling (gTile)"

_MODIFIERS = {
    "primary": "Ctrl", "control": "Ctrl", "ctrl": "Ctrl",
    "shift": "Shift",
    "alt": "Alt", "mod1": "Alt",
    "super": "Super", "mod4": "Super",
    "meta": "Meta", "hyper": "Hyper",
}
_KEYS = {
    "super_l": "Super", "super_r": "Super",
    "return": "Enter", "kp_enter": "Keypad Enter", "space": "Space", "tab": "Tab",
    "escape": "Esc", "delete": "Delete", "backspace": "Backspace", "insert": "Insert",
    "home": "Home", "end": "End", "page_up": "Page Up", "page_down": "Page Down",
    "prior": "Page Up", "next": "Page Down", "print": "Print Screen",
    "left": "Left", "right": "Right", "up": "Up", "down": "Down",
    "comma": ",", "period": ".", "grave": "`", "minus": "-", "equal": "=",
    "slash": "/", "backslash": "\\", "semicolon": ";", "apostrophe": "'",
    "bracketleft": "[", "bracketright": "]", "plus": "+",
    # Cinnamon's name for whichever key sits above Tab: ` on a US keyboard,
    # something else elsewhere, so named as the docs name it.
    "above_tab": "the key left of 1",
}

# The keypad's keys by their Num Lock-off names (KP_End is the 1 key): the
# digit printed on the key is what anyone looks for (gTile tiles with them).
_KEYPAD = {
    "insert": "0", "end": "1", "down": "2", "next": "3", "page_down": "3", "left": "4",
    "begin": "5", "right": "6", "home": "7", "up": "8", "prior": "9", "page_up": "9",
    "delete": ".", "decimal": ".", "add": "+", "subtract": "-", "multiply": "*", "divide": "/",
}


def format_key(key):
    """One X key name as a person would write it: "Return" -> "Enter",
    "comma" -> ",", "g" -> "G", "KP_1" -> "Keypad 1"."""
    known = _KEYS.get(key.lower())
    if known:
        return known
    if key.lower().startswith("kp_"):
        rest = key[3:]
        return "Keypad " + _KEYPAD.get(rest.lower(), rest)
    if len(key) == 1:
        return key.upper()
    return key.replace("_", " ")


def format_accel(accel):
    """One GTK accelerator ("<Primary><Shift>g") as "Ctrl + Shift + G", or
    "" for one there's nothing to press for: empty, or a hardware-only key
    (XF86AudioPlay and the like, on a keyboard's media keys)."""
    accel = accel.strip()
    mods = re.findall(r"<([^>]+)>", accel)
    key = re.sub(r"<[^>]+>", "", accel)
    if not key or key.startswith("XF86"):
        return ""
    parts = [_MODIFIERS.get(m.lower(), m) for m in mods] + [format_key(key)]
    return " + ".join(parts)


def format_accels(accels):
    """Several accelerators for one hotkey, as "Super + R or Super + Alt +
    Space", without repeats (Super_L and Super_R are both "Super")."""
    out = []
    for accel in accels:
        text = format_accel(accel)
        if text and text not in out:
            out.append(text)
    return " or ".join(out)


def parse_cs_keyboard(source):
    """Cinnamon's keyboard settings module (its source text) as
    ([(label, schema, key, category id)], {category id: top-level group
    label}). Read with ast, never run. Anything it can't make sense of is
    skipped; a file it can't parse at all gives ([], {})."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return [], {}
    constants, tables = {}, {}
    for node in tree.body:
        if not isinstance(node, ast.Assign) or len(node.targets) != 1 or not isinstance(node.targets[0], ast.Name):
            continue
        name = node.targets[0].id
        if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            constants[name] = node.value.value
        elif name in ("KEYBINDINGS", "CATEGORIES") and isinstance(node.value, ast.List):
            tables[name] = node.value.elts

    def text(node):
        # _("Label") or a plain string or a module-level string constant.
        if isinstance(node, ast.Call) and node.args:
            node = node.args[0]
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name):
            return constants.get(node.id)
        return None

    parents, labels = {}, {}
    for row in tables.get("CATEGORIES", []):
        if not isinstance(row, ast.List) or len(row.elts) < 3:
            continue
        label, cat_id = text(row.elts[0]), text(row.elts[1])
        if label and cat_id:
            labels[cat_id] = label
            parents[cat_id] = text(row.elts[2])
    groups = {}
    for cat_id in labels:
        top, seen = cat_id, set()
        while parents.get(top) and top not in seen:
            seen.add(top)
            top = parents[top]
        groups[cat_id] = labels.get(top, labels[cat_id])

    bindings = []
    for row in tables.get("KEYBINDINGS", []):
        if not isinstance(row, ast.List) or len(row.elts) < 4:
            continue
        fields = [text(e) for e in row.elts[:4]]
        if all(fields):
            bindings.append(tuple(fields))
    return bindings, groups


def stock_slots(path=STOCK_FILE):
    """The slot numbers of OhMyDebn's stock custom hotkeys."""
    try:
        with open(path) as f:
            return {int(m.group(1)) for m in (re.match(r"keybinding-custom (\d+) ", line) for line in f) if m}
    except OSError:
        return set()


def spice_keybindings(uuid):
    """{setting key: (value, description)} for every keybinding setting of
    a Cinnamon applet or extension (the first instance's settings file),
    or {} if it has none."""
    for path in sorted(glob.glob(os.path.join(SPICES, uuid, "*.json"))):
        try:
            with open(path) as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue
        return {
            key: (str(item.get("value") or ""), item.get("description") or key)
            for key, item in data.items()
            if isinstance(item, dict) and item.get("type") == "keybinding"
        }
    return {}


class GioReader:
    """gsettings, read in this process: one Gio call per key rather than a
    gsettings process per key, so the list opens as fast as the menu does.
    A schema or key this Cinnamon doesn't have reads as None."""

    def __init__(self):
        from gi.repository import Gio
        self.Gio = Gio
        self.source = Gio.SettingsSchemaSource.get_default()
        self._settings = {}

    def _get(self, schema, path=None):
        cache_key = (schema, path)
        if cache_key not in self._settings:
            found = self.source.lookup(schema, True) if self.source else None
            if found is None:
                self._settings[cache_key] = None
            elif path:
                self._settings[cache_key] = self.Gio.Settings.new_full(found, None, path)
            else:
                self._settings[cache_key] = self.Gio.Settings.new_full(found, None, None)
        return self._settings[cache_key]

    def strv(self, schema, key):
        settings = self._get(schema)
        if settings is None or not settings.props.settings_schema.has_key(key):
            return None
        value = settings.get_value(key)
        return list(value.unpack()) if value.get_type_string() == "as" else None

    def custom(self, slot_id):
        """(name, command, [accelerators]) of one custom hotkey."""
        settings = self._get(CUSTOM_SCHEMA, CUSTOM_PATH.format(slot_id))
        if settings is None:
            return None
        return settings.get_string("name"), settings.get_string("command"), list(settings.get_strv("binding"))


def load_hotkeys(reader=None, cs_keyboard=CS_KEYBOARD, stock_file=STOCK_FILE):
    """Every hotkey to list, in order: OhMyDebn's, the user's own, gTile's,
    then Cinnamon's by its own categories, ending with the docs row."""
    reader = reader or GioReader()
    stock = stock_slots(stock_file)
    ohmydebn, yours = [], []

    menu_key = spice_keybindings("menu@cinnamon.org").get("overlay-key")
    if menu_key:
        keys = format_accels(menu_key[0].split("::"))
        if keys:
            ohmydebn.append(Hotkey(keys, "Cinnamon menu", GROUP_OHMYDEBN, None))

    for slot_id in reader.strv(KEYBINDINGS_SCHEMA, "custom-list") or []:
        if slot_id == "__dummy__":
            continue
        custom = reader.custom(slot_id)
        if not custom:
            continue
        name, command, accels = custom
        keys = format_accels(accels)
        if not keys:
            continue
        m = re.fullmatch(r"custom-(\d+)", slot_id)
        if m and int(m.group(1)) in stock:
            ohmydebn.append((int(m.group(1)), Hotkey(keys, name, GROUP_OHMYDEBN, command)))
        else:
            yours.append(Hotkey(keys, name, GROUP_YOURS, command))
    # Stock slots in their own order (custom-list keeps the order they were
    # added in, which isn't), after the menu key.
    head = [h for h in ohmydebn if isinstance(h, Hotkey)]
    slots = sorted((h for h in ohmydebn if not isinstance(h, Hotkey)), key=lambda pair: pair[0])
    hotkeys = head + [h for _slot, h in slots] + yours

    if "gTile@OhMyDebn" in (reader.strv("org.cinnamon", "enabled-extensions") or []):
        for value, description in spice_keybindings("gTile@OhMyDebn").values():
            keys = format_accels(value.split("::"))
            if keys:
                hotkeys.append(Hotkey(keys, description, GROUP_GTILE, None))

    try:
        with open(cs_keyboard) as f:
            bindings, groups = parse_cs_keyboard(f.read())
    except OSError:
        bindings, groups = [], {}
    translate = gettext.translation("cinnamon", fallback=True).gettext
    by_group = {}
    for label, schema, key, category in bindings:
        keys = format_accels(reader.strv(schema, key) or [])
        if keys:
            group = translate(groups.get(category, category))
            by_group.setdefault(group, []).append(Hotkey(keys, translate(label), group, None))
    for group_hotkeys in by_group.values():
        hotkeys += group_hotkeys

    hotkeys.append(Hotkey("", "More, including shortcuts inside apps: ohmydebn.org/hotkeys", "", f"{WEBAPP} {DOCS_URL}"))
    return hotkeys


def matches(hotkey, query):
    """Whether a hotkey fits what's typed: every word somewhere in its keys,
    name or group, so "super shift" and "workspace 2" both narrow it down."""
    haystack = f"{hotkey.keys} {hotkey.name} {hotkey.group}".lower()
    return all(word in haystack for word in query.lower().split())
