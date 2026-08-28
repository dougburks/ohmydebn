#!/usr/bin/python3
#
# Pure-logic regression tests for bin/ohmydebn-virtmanager-passt-upgrade:
# the virsh/virt-xml-driving functions, not the GTK window (see
# test-python-pickers.py's own header comment for why this suite follows
# the same "no real display needed" split - none of what's tested here
# touches Gtk/Gdk at all). Monkeypatches the module's own subprocess.run,
# same technique test-python-pickers.py uses for theme-carousel's
# remove_current_theme().

import os
import subprocess
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


print("=== ohmydebn-virtmanager-passt-upgrade (pure logic) ===")
pu = SourceFileLoader("ohmydebn-virtmanager-passt-upgrade", os.path.join(BIN, "ohmydebn-virtmanager-passt-upgrade")).load_module()

original_run = pu.subprocess.run


class FakeCompleted:
    def __init__(self, stdout="", returncode=0):
        self.stdout = stdout
        self.stderr = ""
        self.returncode = returncode


def fake_run_returning(stdout, returncode=0):
    def _fake(argv, capture_output=True, text=True, check=False):
        return FakeCompleted(stdout, returncode)

    return _fake


# XML fixtures - the first two are byte-for-byte the shape confirmed live
# via `virsh --connect qemu:///session dumpxml` against real VMs (one
# already upgraded, one not), not hand-guessed.
XML_WITH_PASST = """<domain type='kvm'>
  <name>debian13</name>
  <devices>
    <interface type='user'>
      <mac address='52:54:00:dc:87:92'/>
      <model type='virtio'/>
      <backend type='passt'/>
    </interface>
  </devices>
</domain>"""

XML_WITHOUT_PASST = """<domain type='kvm'>
  <name>archlinux</name>
  <devices>
    <interface type='user'>
      <mac address='52:54:00:af:c9:45'/>
      <model type='virtio'/>
    </interface>
  </devices>
</domain>"""

XML_NOT_APPLICABLE = """<domain type='kvm'>
  <name>system-mode-vm</name>
  <devices>
    <interface type='network'>
      <mac address='52:54:00:11:22:33'/>
      <source network='default'/>
    </interface>
  </devices>
</domain>"""

XML_MIXED_INTERFACES = """<domain type='kvm'>
  <name>multi-nic</name>
  <devices>
    <interface type='user'>
      <mac address='52:54:00:aa:aa:aa'/>
      <backend type='passt'/>
    </interface>
    <interface type='user'>
      <mac address='52:54:00:bb:bb:bb'/>
    </interface>
  </devices>
</domain>"""

try:
    pu.subprocess.run = fake_run_returning(XML_WITH_PASST)
    check_eq("get_passt_status: already-upgraded VM", pu.get_passt_status("debian13"), ("passt", []))

    pu.subprocess.run = fake_run_returning(XML_WITHOUT_PASST)
    check_eq(
        "get_passt_status: user-mode NIC missing the passt backend",
        pu.get_passt_status("archlinux"),
        ("needs_upgrade", ["52:54:00:af:c9:45"]),
    )

    pu.subprocess.run = fake_run_returning(XML_NOT_APPLICABLE)
    check_eq(
        "get_passt_status: no user-mode interface at all (e.g. bridged/network type)",
        pu.get_passt_status("system-mode-vm"),
        ("not_applicable", []),
    )

    pu.subprocess.run = fake_run_returning(XML_MIXED_INTERFACES)
    check_eq(
        "get_passt_status: only the interface still missing passt is reported",
        pu.get_passt_status("multi-nic"),
        ("needs_upgrade", ["52:54:00:bb:bb:bb"]),
    )

    pu.subprocess.run = fake_run_returning("", returncode=1)
    check_eq("get_passt_status: dumpxml failure (nonexistent VM) doesn't crash", pu.get_passt_status("no-such-vm"), ("unknown", []))

    pu.subprocess.run = fake_run_returning("not even xml {{{")
    check_eq("get_passt_status: unparseable XML doesn't crash", pu.get_passt_status("garbled"), ("unknown", []))

    pu.subprocess.run = fake_run_returning("debian13\narchlinux\n\nkali\n")
    check_eq(
        "list_vm_names: parses newline-separated names, skips blank lines",
        pu.list_vm_names(),
        ["debian13", "archlinux", "kali"],
    )

    pu.subprocess.run = fake_run_returning("shut off\n")
    check_eq("get_vm_state: strips trailing newline/whitespace", pu.get_vm_state("archlinux"), "shut off")

    pu.subprocess.run = fake_run_returning("")
    check_eq("get_vm_state: empty output falls back to 'unknown' rather than ''", pu.get_vm_state("mystery-vm"), "unknown")

    upgrade_calls = []

    def fake_upgrade_run(argv, capture_output=True, text=True, check=False):
        upgrade_calls.append(argv)
        return FakeCompleted()

    pu.subprocess.run = fake_upgrade_run
    pu.upgrade_to_passt("archlinux", ["52:54:00:af:c9:45"])
    check_eq(
        "upgrade_to_passt: calls virt-xml with --edit --network mac=...,backend.type=passt",
        upgrade_calls,
        [[pu.VIRT_XML, "--connect", pu.CONNECT, "archlinux", "--edit", "--network", "mac=52:54:00:af:c9:45,backend.type=passt"]],
    )

    upgrade_calls.clear()
    pu.upgrade_to_passt("multi-nic", ["52:54:00:aa:aa:aa", "52:54:00:bb:bb:bb"])
    check_eq("upgrade_to_passt: one virt-xml call per missing interface, not a single combined one", len(upgrade_calls), 2)

    def fake_failing_run(argv, capture_output=True, text=True, check=False):
        raise subprocess.CalledProcessError(1, argv, output="", stderr="virt-xml: error: no such domain")

    pu.subprocess.run = fake_failing_run
    try:
        pu.upgrade_to_passt("gone-vm", ["52:54:00:00:00:00"])
        check("upgrade_to_passt: a virt-xml failure propagates rather than failing silently", False)
    except subprocess.CalledProcessError:
        check("upgrade_to_passt: a virt-xml failure propagates rather than failing silently", True)
finally:
    pu.subprocess.run = original_run

print()
print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
raise SystemExit(0 if TESTS_FAILED == 0 else 1)
