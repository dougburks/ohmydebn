#!/usr/bin/python3
#
# Tests for bin/ohmydebn_glib.py. GLib.unix_signal_add made newer PyGObject
# (Python 3.14's, on Linux Mint 27) warn "PyGIDeprecationWarning:
# GLib.unix_signal_add is deprecated; use GLibUnix.signal_add instead" on
# every start of the theme intro, the update window and the speed tests,
# while older PyGObject (Debian 13, Mint 22) has no GLibUnix.signal_add.
# The helper is loaded against stand-in gi modules for each case, then
# against this machine's real PyGObject; and no OhMyDebn script may call
# the old function directly any more.

import glob
import importlib.util
import os
import sys
import types
import warnings

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODULE = os.path.join(REPO_ROOT, "bin", "ohmydebn_glib.py")

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


def load(name):
    """Runs the helper as a fresh module."""
    spec = importlib.util.spec_from_file_location(name, MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def old_signal_add(*args):
    return "old"


def new_signal_add(*args):
    return "new"


def load_with(glibunix):
    """Loads the helper with a stand-in gi: glibunix is a GLibUnix module,
    None for no GLibUnix typelib at all."""
    saved = {k: sys.modules.get(k) for k in ("gi", "gi.repository", "gi.repository.GLib", "gi.repository.GLibUnix")}
    gi = types.ModuleType("gi")
    repo = types.ModuleType("gi.repository")
    glib = types.ModuleType("gi.repository.GLib")
    glib.unix_signal_add = old_signal_add
    repo.GLib = glib

    def require_version(name, version):
        if name == "GLibUnix" and glibunix is None:
            raise ValueError("Namespace GLibUnix not available")

    gi.require_version = require_version
    gi.repository = repo
    sys.modules.update({"gi": gi, "gi.repository": repo, "gi.repository.GLib": glib})
    if glibunix is not None:
        repo.GLibUnix = glibunix
        sys.modules["gi.repository.GLibUnix"] = glibunix
    else:
        sys.modules.pop("gi.repository.GLibUnix", None)
    try:
        return load("ohmydebn_glib_test")
    finally:
        for k, v in saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v


print("=== bin/ohmydebn_glib.py ===")

newer = types.ModuleType("gi.repository.GLibUnix")
newer.signal_add = new_signal_add
check("newer PyGObject (GLibUnix.signal_add): the new call", load_with(newer).unix_signal_add() == "new")

debian13 = types.ModuleType("gi.repository.GLibUnix")  # the typelib, without signal_add
check("Debian 13 (GLibUnix without signal_add): GLib's", load_with(debian13).unix_signal_add() == "old")

check("no GLibUnix at all: GLib's", load_with(None).unix_signal_add() == "old")

# This machine's own PyGObject: loads without a deprecation warning, and
# gives something callable.
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter("always")
    real = load("ohmydebn_glib_real")
check("real PyGObject: callable", callable(real.unix_signal_add))
check("real PyGObject: no deprecation warning",
      not [w for w in caught if "unix_signal_add" in str(w.message)])

direct = []
for path in glob.glob(os.path.join(REPO_ROOT, "bin", "*")):
    if os.path.basename(path) == "ohmydebn_glib.py" or not os.path.isfile(path):
        continue
    try:
        text = open(path, encoding="utf-8").read()
    except UnicodeDecodeError:
        continue
    for n, line in enumerate(text.splitlines(), 1):
        if "GLib.unix_signal_add(" in line and not line.lstrip().startswith("#"):
            direct.append(f"{os.path.basename(path)}:{n}")
check("no script calls GLib.unix_signal_add directly" + (f" ({', '.join(direct)})" if direct else ""), not direct)

print(f"\n{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
