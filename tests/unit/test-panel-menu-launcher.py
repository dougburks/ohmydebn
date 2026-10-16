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
    check_eq("main: the launcher's only app is the OhMyDebn Menu", settings["launcherList"]["value"], ["ohmydebn-menu.desktop"])
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

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
raise SystemExit(1 if TESTS_FAILED else 0)
