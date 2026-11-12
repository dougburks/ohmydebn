#!/usr/bin/python3
#
# Tests for the offline half of tests/distro-checks.py: how it reads what
# OhMyDebn installs out of the repo. The distro checks themselves need the
# network and run before a release, not here, so a new installer or a
# reworded apt line that the parser misreads would otherwise go unnoticed
# until then (or never: an installer it skips is simply not checked).

import os
import re
import sys
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
dc = SourceFileLoader("distro_checks", os.path.join(REPO_ROOT, "tests", "distro-checks.py")).load_module()

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


print("=== tests/distro-checks.py ===")

found = dc.installers()

# Every installer that runs apt itself is either read or known to be a
# vendor's: none may fall through unchecked.
bindir = os.path.join(REPO_ROOT, "bin")
for f in sorted(os.listdir(bindir)):
    m = re.fullmatch(r"ohmydebn-(.+)-install", f)
    if not m or m.group(1) in dc.NOT_APPS:
        continue
    text = open(os.path.join(bindir, f)).read()
    if re.search(r"/usr/bin/apt .*\binstall\b|ohmydebn-apt-install-deb", text):
        check(f"{m.group(1)}: read", m.group(1) in found)

for app, spec in found.items():
    if spec == "vendor":
        continue
    pkgs, _ = spec
    check(f"{app}: its packages are known", pkgs is not None)
    if pkgs:
        check(f"{app}: no shell left in its package names", not any(re.search(r'[$"\'()]', p) for p in pkgs))

check("chromium: --no-install-recommends read as a flag, not a package",
      found["chromium"] == (["chromium|chromium-browser"], ["--no-install-recommends"]))
check("remote-desktop-server: xrdp and xorgxrdp", found["remote-desktop-server"][0] == ["xrdp", "xorgxrdp"])
check("tailscale: a vendor repo", found["tailscale"] == "vendor")
check("code: a vendor .deb", found["code"] == "vendor")
check("brave-browser: a vendor repo through its own helper", found["brave-browser"] == "vendor")
check("podman: read from ohmydebn-podman-installed", found["podman"][0] == dc.array_from("bin/ohmydebn-podman-installed"))

# The optional packages, read the same way tests/lib/extract-packages.sh
# reads them for apt-checks.sh and consistency.sh.
deps = dc.array_from("install/packaging/dependencies.sh")
check("dependencies.sh: read past the parentheses in its comments", len(deps) > 40 and "chrony" in deps)
check("dependencies.sh: no comment text read as a package", all(re.fullmatch(r"[a-z0-9][a-z0-9.+-]*", p) for p in deps))
power = dc.power_user_packages()
check("power-user.sh: its packages", "keepassxc-minimal" in power and "iperf3" in power)
check("power-user.sh: no shell read as a package", all(re.fullmatch(r"[a-z0-9][a-z0-9.+-]*", p) for p in power))

check("pick: first alternative the distro has", dc.pick("chromium|chromium-browser", {"chromium-browser"}) == "chromium-browser")
check("pick: none of them is missing", dc.pick("chromium|chromium-browser", set()) is None)
check("pick: an optional one that's missing is left out", dc.pick("docker-cli?", set()) == "")

out = """Inst libfoo1 (1.0 Debian:13 [amd64])
Inst foo [0.9] (1.0 Debian:13 [amd64])
Remv bar [2.0]
"""
check("removals: read from apt's simulation", dc.removals(out) == ["bar"])

for (distro, app) in dc.KNOWN:
    check(f"KNOWN: {distro} is a distro this checks", distro in dc.DISTROS)
    check(f"KNOWN: {app} is an installer this checks", app in found)

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
