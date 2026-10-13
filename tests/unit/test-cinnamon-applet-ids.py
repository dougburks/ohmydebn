#!/usr/bin/python3
#
# Unit tests for bin/ohmydebn-cinnamon-applet-ids, which renumbers panel
# applets that share an instance ID. OhMyDebn's panel before 4.10.0 gave
# network and the workspace switcher both 10, and the window list and
# power both 12. The planning is pure, so it's tested directly; the
# gsettings calls aren't exercised here.

import json
import os
import shutil
import tempfile
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ids = SourceFileLoader("applet_ids", os.path.join(REPO_ROOT, "bin", "ohmydebn-cinnamon-applet-ids")).load_module()

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


print("=== bin/ohmydebn-cinnamon-applet-ids ===")

# The panel OhMyDebn seeded before 4.10.0.
OLD_SEED = [
    "panel1:left:0:menu@cinnamon.org:0", "panel1:left:3:window-list@cinnamon.org:12",
    "panel1:right:0:systray@cinnamon.org:3", "panel1:right:1:xapp-status@cinnamon.org:4",
    "panel1:right:2:notifications@cinnamon.org:5", "panel1:right:3:printers@cinnamon.org:6",
    "panel1:right:4:removable-drives@cinnamon.org:7", "panel1:right:5:keyboard@cinnamon.org:8",
    "panel1:right:6:favorites@cinnamon.org:9", "panel1:right:7:network@cinnamon.org:10",
    "panel1:right:8:sound@cinnamon.org:11", "panel1:right:9:power@cinnamon.org:12",
    "panel1:right:10:calendar@cinnamon.org:13", "panel1:left:2:workspace-switcher@cinnamon.org:10",
]
MULTI = {"workspace-switcher@cinnamon.org", "window-list@cinnamon.org"}


def multi(uuid):
    return uuid in MULTI


def ids_of(entries):
    return [e.split(":")[4] for e in entries]


new, moves, next_id = ids.plan(OLD_SEED, 14, multi)
check_eq("old seed: every ID is unique afterwards", len(set(ids_of(new))), len(new))
check_eq("old seed: network (single-instance) is the one renumbered, not the workspace switcher",
         [e for e in new if "network" in e], ["panel1:right:7:network@cinnamon.org:14"])
check_eq("old seed: power (single-instance) renumbered, the window list keeps 12",
         [e for e in new if "power" in e or "window-list" in e],
         ["panel1:left:3:window-list@cinnamon.org:12", "panel1:right:9:power@cinnamon.org:15"])
check_eq("old seed: no settings file has to move (single-instance applets use <uuid>.json)", moves, [])
check_eq("old seed: next-applet-id moves past the new IDs", next_id, 16)
check_eq("old seed: positions, panels and every other applet unchanged",
         [e for e in new if "network" not in e and "power" not in e],
         [e for e in OLD_SEED if "network" not in e and "power" not in e])

# This machine's panel at the time: window list already moved to 16 by
# Cinnamon, next-applet-id 17 - only the network pair is left.
here = [e if "window-list" not in e else "panel1:left:3:window-list@cinnamon.org:16" for e in OLD_SEED]
here = [e for e in here if "power" not in e] + ["panel1:right:11:power@cinnamon.org:12"]
new, moves, next_id = ids.plan(here, 17, multi)
check_eq("one pair left: only network changes, to the next free ID",
         [(a, b) for a, b in zip(here, new) if a != b],
         [("panel1:right:7:network@cinnamon.org:10", "panel1:right:7:network@cinnamon.org:17")])

check_eq("unique IDs already: nothing changes", ids.plan(new, next_id, multi)[0], new)

# Two multi-instance applets sharing an ID: one keeps it, the other's
# settings file moves to its new ID.
pair = ["panel1:left:0:workspace-switcher@cinnamon.org:5", "panel1:left:1:window-list@cinnamon.org:5"]
new, moves, next_id = ids.plan(pair, 6, multi)
check_eq("two multi-instance applets: the first keeps the ID", new[0], pair[0])
check_eq("two multi-instance applets: the other's settings file follows it",
         moves, [("window-list@cinnamon.org", "5", "6")])

check_eq("next-applet-id below the IDs in use: new IDs still don't collide",
         ids.plan(["p:l:0:a@x:20", "p:l:1:b@x:20"], 3, lambda u: False)[0][1], "p:l:1:b@x:21")
check_eq("an entry without an ID (Cinnamon's old 4-part form) is left alone",
         ids.plan(["p:l:0:a@x", "p:l:1:b@x:7"], 8, multi)[0], ["p:l:0:a@x", "p:l:1:b@x:7"])

check_eq("gsettings list read", ids.parse_strv("['a:b:0:c:1', 'a:b:1:d:2']\n"), ["a:b:0:c:1", "a:b:1:d:2"])
check_eq("gsettings empty list read", ids.parse_strv("@as []"), [])
check_eq("gsettings list written back the same", ids.format_strv(["a:b:0:c:1", "a:b:1:d:2"]),
         "['a:b:0:c:1', 'a:b:1:d:2']")

# Cinnamon's multi-instance rule, from real metadata files: a user copy in
# ~/.local/share wins over the system one, missing max-instances means 1.
user, system = tempfile.mkdtemp(), tempfile.mkdtemp()
for base, uuid, meta in ((system, "one@x", {}), (system, "many@x", {"max-instances": -1}),
                         (system, "over@x", {}), (user, "over@x", {"max-instances": 3})):
    os.makedirs(os.path.join(base, uuid))
    with open(os.path.join(base, uuid, "metadata.json"), "w") as f:
        json.dump(meta, f)
dirs = (user, system)
check_eq("metadata without max-instances: single-instance", ids.is_multi_instance("one@x", dirs), False)
check_eq("max-instances -1: multi-instance", ids.is_multi_instance("many@x", dirs), True)
check_eq("a user-installed copy's metadata wins", ids.is_multi_instance("over@x", dirs), True)
check_eq("no metadata at all: treated as multi-instance (its file moves with it)",
         ids.is_multi_instance("missing@x", dirs), True)
shutil.rmtree(user)
shutil.rmtree(system)

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
raise SystemExit(0 if TESTS_FAILED == 0 else 1)
