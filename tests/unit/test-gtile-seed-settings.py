#!/usr/bin/python3
#
# Guards config/cinnamon/spices/gTile@OhMyDebn/gTile@OhMyDebn.json, the
# gTile settings file install/config/cinnamon.sh seeds into a new user's
# spice directory. It's a snapshot of an old upstream gTile settings file,
# and four of its checkboxes stored their values as the STRINGS "true" /
# "false". Cinnamon's settings upgrade keeps stored values as they are
# (its sanity check only validates spinbuttons and comboboxes), the
# extension reads them raw, and in JavaScript the string "false" is
# truthy - so on a fresh install "UI always centered on monitor" and
# "Show UI on all monitors" behaved as ON while showing as off, and a
# user couldn't toggle their way out of it. Real booleans only.

import json
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SEED = os.path.join(REPO_ROOT, "config", "cinnamon", "spices", "gTile@OhMyDebn", "gTile@OhMyDebn.json")

TESTS_RUN = 0
TESTS_FAILED = 0


def check(desc, condition, detail=""):
    global TESTS_RUN, TESTS_FAILED
    TESTS_RUN += 1
    if condition:
        print("  ok - " + desc)
    else:
        print("  FAIL - " + desc + ((" (" + detail + ")") if detail else ""))
        TESTS_FAILED += 1


print("=== gTile seed settings: checkbox values are real booleans ===")

with open(SEED) as fp:
    seed = json.load(fp)

checkboxes = {k: v for k, v in seed.items() if isinstance(v, dict) and v.get("type") == "checkbox"}
check("seed has checkbox settings to validate", len(checkboxes) > 0)

bad = []
for key, entry in sorted(checkboxes.items()):
    for field in ("default", "value"):
        if field in entry and not isinstance(entry[field], bool):
            bad.append("%s.%s=%r" % (key, field, entry[field]))
check("every checkbox default/value is a bool (a quoted \"false\" is truthy in the extension)",
      not bad, ", ".join(bad))

# The two settings that visibly misbehaved as strings, pinned by name so a
# future re-snapshot of the file can't quietly reintroduce them.
for key in ("useMonitorCenter", "showGridOnAllMonitors"):
    check("%s is a real false (was the string \"false\")" % key,
          checkboxes.get(key, {}).get("value") is False, repr(checkboxes.get(key, {}).get("value")))

print()
print("%d/%d passed" % (TESTS_RUN - TESTS_FAILED, TESTS_RUN))
raise SystemExit(0 if TESTS_FAILED == 0 else 1)
