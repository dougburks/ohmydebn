#!/usr/bin/python3
#
# Unit tests for bin/ohmydebn-panel-menu-launcher, which adds the OhMyDebn
# Menu to the panel as a panel launcher right after the Cinnamon menu. The
# planning is pure, so it's tested directly; main() runs against a fake
# gsettings and a scratch spices directory.

import json
import os
import shutil
import subprocess
import tempfile
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
pml = SourceFileLoader("panel_menu_launcher", os.path.join(REPO_ROOT, "bin", "ohmydebn-panel-menu-launcher")).load_module()

TESTS_RUN = 0
TESTS_FAILED = 0


def check_eq(desc, actual, expected):
    global TESTS_RUN, TESTS_FAILED
    TESTS_RUN += 1
    if actual == expected:
        print(f"  ok - {desc}")
    else:
        print(f"  FAIL - {desc}\n    expected: {expected!r}\n    actual:   {actual!r}")
        TESTS_FAILED += 1


print("=== bin/ohmydebn-panel-menu-launcher ===")

# The panel install/config/cinnamon.sh seeds (left:1 is free).
SEED = [
    "panel1:left:0:menu@cinnamon.org:0", "panel1:left:3:window-list@cinnamon.org:15",
    "panel1:right:0:systray@cinnamon.org:3", "panel1:right:10:calendar@cinnamon.org:13",
    "panel1:left:2:workspace-switcher@cinnamon.org:14",
]
NONE = lambda applet_id: []  # noqa: E731 - no panel launchers configured

# Scenario 1: the seeded panel - added at left:1, after the Cinnamon menu
# in the list as well, with an ID above every one in use.
new, new_id = pml.plan(SEED, 1, NONE)
check_eq("seeded panel: new ID above all in use", new_id, 16)
check_eq("seeded panel: added right after the Cinnamon menu, nothing moved", new, [
    "panel1:left:0:menu@cinnamon.org:0", "panel1:left:1:panel-launchers@cinnamon.org:16",
    "panel1:left:3:window-list@cinnamon.org:15", "panel1:right:0:systray@cinnamon.org:3",
    "panel1:right:10:calendar@cinnamon.org:13", "panel1:left:2:workspace-switcher@cinnamon.org:14",
])

# Scenario 2: Cinnamon's counter is already past every ID in use - it wins.
check_eq("next-applet-id higher than the IDs in use: used", pml.plan(SEED, 40, NONE)[1], 40)

# Scenario 3: the place after the Cinnamon menu is taken - that applet and
# the ones after it on the same side move along one; the other side and
# other panels don't.
CROWDED = [
    "panel1:left:0:menu@cinnamon.org:0", "panel1:left:1:show-desktop@cinnamon.org:1",
    "panel1:left:2:workspace-switcher@cinnamon.org:2", "panel1:right:1:calendar@cinnamon.org:3",
    "panel2:left:1:window-list@cinnamon.org:4",
]
new, new_id = pml.plan(CROWDED, 5, NONE)
check_eq("crowded panel: later applets on that side move along", new, [
    "panel1:left:0:menu@cinnamon.org:0", "panel1:left:1:panel-launchers@cinnamon.org:5",
    "panel1:left:2:show-desktop@cinnamon.org:1", "panel1:left:3:workspace-switcher@cinnamon.org:2",
    "panel1:right:1:calendar@cinnamon.org:3", "panel2:left:1:window-list@cinnamon.org:4",
])

# Scenario 4: the Cinnamon menu somewhere else (a bottom panel's right
# side) - the launcher goes next to it there.
MOVED = ["panel2:right:4:menu@cinnamon.org:7", "panel1:left:0:window-list@cinnamon.org:8"]
new, _ = pml.plan(MOVED, 9, NONE)
check_eq("menu moved: launcher follows it", new[1], "panel2:right:5:panel-launchers@cinnamon.org:9")

# Scenario 5: a panel launcher already has the OhMyDebn Menu - nothing.
WITH_LAUNCHER = SEED + ["panel1:left:1:panel-launchers@cinnamon.org:20"]
check_eq("already on the panel: nothing changes",
         pml.plan(WITH_LAUNCHER, 21, lambda i: ["ohmydebn-menu.desktop"] if i == "20" else []), (None, None))

# Scenario 6: a panel launcher with other apps only - ours is still added,
# as its own launcher, and the user's is left as it is.
new, new_id = pml.plan(WITH_LAUNCHER, 21, lambda i: ["firefox.desktop"])
check_eq("other launchers only: ours added", new_id, 21)
check_eq("other launchers only: theirs kept, moved along one", "panel1:left:2:panel-launchers@cinnamon.org:20" in new, True)

# Scenario 7: no Cinnamon menu on any panel - nothing.
check_eq("no Cinnamon menu: nothing changes", pml.plan(SEED[1:], 1, NONE), (None, None))

# Scenario 8: launcher_list reads an instance's settings file, and treats a
# missing or broken one as empty.
tmp = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(tmp, "panel-launchers@cinnamon.org"))
    with open(os.path.join(tmp, "panel-launchers@cinnamon.org", "20.json"), "w") as f:
        json.dump({"launcherList": {"type": "generic", "value": ["ohmydebn-menu.desktop", "nemo.desktop"]}}, f)
    with open(os.path.join(tmp, "panel-launchers@cinnamon.org", "21.json"), "w") as f:
        f.write("{ broken")
    check_eq("launcher_list: reads the value", pml.launcher_list("20", tmp), ["ohmydebn-menu.desktop", "nemo.desktop"])
    check_eq("launcher_list: broken file is empty", pml.launcher_list("21", tmp), [])
    check_eq("launcher_list: missing file is empty", pml.launcher_list("22", tmp), [])
finally:
    shutil.rmtree(tmp)


# main() against a fake gsettings: the settings file is written, then the
# counter and the applet list are set; a second run changes nothing.
class FakeGsettings:
    def __init__(self, applets, next_id):
        self.values = {"enabled-applets": pml.format_strv(applets), "next-applet-id": f"uint32 {next_id}"}
        self.sets = []
        self.fail = False

    def __call__(self, *args):
        if self.fail:
            raise subprocess.CalledProcessError(1, "gsettings")
        if args[0] == "get":
            return self.values[args[2]]
        self.sets.append((args[2], args[3]))
        self.values[args[2]] = args[3] if args[2] == "enabled-applets" else f"uint32 {args[3]}"
        return ""


tmp = tempfile.mkdtemp()
try:
    pml.SPICES_DIR = tmp
    fake = FakeGsettings(SEED, 1)
    pml.gsettings = fake
    check_eq("main: succeeds", pml.main(), 0)
    with open(os.path.join(tmp, "panel-launchers@cinnamon.org", "16.json")) as f:
        settings = json.load(f)
    check_eq("main: the launcher has the OhMyDebn Menu, then the AI Assistant", settings["launcherList"]["value"],
             ["ohmydebn-menu.desktop", "ohmydebn-ai.desktop"])
    check_eq("main: counter set past the new ID, then the applet added",
             [key for key, _ in fake.sets], ["next-applet-id", "enabled-applets"])
    check_eq("main: counter value", fake.sets[0][1], "17")
    check_eq("main: applet in the list", "panel1:left:1:panel-launchers@cinnamon.org:16" in fake.values["enabled-applets"], True)
    fake.sets = []
    check_eq("main, second run: succeeds", pml.main(), 0)
    check_eq("main, second run: nothing set", fake.sets, [])
    fake.fail = True
    check_eq("main, no session bus: exit 1 so the step retries", pml.main(), 1)
finally:
    shutil.rmtree(tmp)

# --- --add-ai: installs that got the OhMyDebn Menu button before the AI
# Assistant existed get it right after, once. ---
print("=== --add-ai ===")
PANEL = SEED + ["panel1:left:1:panel-launchers@cinnamon.org:20", "panel2:left:0:panel-launchers@cinnamon.org:21"]
lists = {"20": ["nemo.desktop", "ohmydebn-menu.desktop", "firefox.desktop"], "21": ["gedit.desktop"]}
check_eq("plan: right after the OhMyDebn Menu, the user's own launchers kept",
         pml.plan_add_ai(PANEL, lambda i: lists.get(i, [])),
         ("20", ["nemo.desktop", "ohmydebn-menu.desktop", "ohmydebn-ai.desktop", "firefox.desktop"]))
check_eq("plan: already in any panel launcher - nothing",
         pml.plan_add_ai(PANEL, lambda i: {"21": ["ohmydebn-ai.desktop"]}.get(i, lists.get(i, []))), (None, None))
check_eq("plan: the OhMyDebn Menu button was removed - nothing (they don't want our buttons)",
         pml.plan_add_ai(PANEL, lambda i: {"20": ["nemo.desktop"]}.get(i, [])), (None, None))
check_eq("plan: a launcher in a settings file but not on the panel doesn't count",
         pml.plan_add_ai(SEED, lambda i: ["ohmydebn-menu.desktop"]), (None, None))

tmp = tempfile.mkdtemp()
saved_argv, saved_tell = list(pml.sys.argv), pml.tell_cinnamon
told = []
try:
    pml.SPICES_DIR = tmp
    os.makedirs(os.path.join(tmp, "panel-launchers@cinnamon.org"))
    path = os.path.join(tmp, "panel-launchers@cinnamon.org", "20.json")
    with open(path, "w") as f:
        json.dump({"launcherList": {"type": "generic", "default": [], "value": ["ohmydebn-menu.desktop"]},
                   "allow-dragging": {"type": "checkbox", "value": False}, "__md5__": "abc"}, f)
    fake = FakeGsettings(SEED + ["panel1:left:1:panel-launchers@cinnamon.org:20"], 21)
    pml.gsettings = fake
    pml.tell_cinnamon = lambda applet_id, launchers: told.append((applet_id, launchers))
    pml.sys.argv = ["ohmydebn-panel-menu-launcher", "--add-ai"]
    check_eq("add-ai: succeeds", pml.main(), 0)
    with open(path) as f:
        settings = json.load(f)
    check_eq("add-ai: the file's list has the AI Assistant after the menu", settings["launcherList"]["value"],
             ["ohmydebn-menu.desktop", "ohmydebn-ai.desktop"])
    check_eq("add-ai: the rest of the file kept", (settings["allow-dragging"]["value"], settings["__md5__"]), (False, "abc"))
    check_eq("add-ai: Cinnamon is told (it doesn't watch the file from Mint 27 on)", told,
             [("20", ["ohmydebn-menu.desktop", "ohmydebn-ai.desktop"])])
    check_eq("add-ai: no applet added or counter moved", fake.sets, [])
    told.clear()
    check_eq("add-ai, second run: succeeds", pml.main(), 0)
    check_eq("add-ai, second run: nothing told", told, [])
    fake.fail = True
    check_eq("add-ai, no session bus: exit 1 so the step retries", pml.main(), 1)
finally:
    pml.sys.argv, pml.tell_cinnamon = saved_argv, saved_tell
    shutil.rmtree(tmp)

check_eq("write_launcher_list: a missing file is False, nothing created",
         (pml.write_launcher_list("99", ["x"], tempfile.gettempdir() + "/no-such-spices"),
          os.path.exists(tempfile.gettempdir() + "/no-such-spices")), (False, False))

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
raise SystemExit(1 if TESTS_FAILED else 0)
