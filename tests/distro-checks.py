#!/usr/bin/python3
#
# distro-checks.py: asks each supported distro's apt whether what OhMyDebn
# installs can actually be installed there. apt-checks.sh only asks this
# machine's apt whether each package exists; this asks every distro's own
# archives, with its own pins, architecture and Recommends setting, whether
# the whole set resolves on top of that distro's base system. That's where
# distro-specific bugs live: LCOS's XLibre can't take xorgxrdp, MX Linux
# and LCOS turn Recommends off, and a package one distro has can be
# missing from another.
#
# Nothing touches this machine's apt or dpkg: each distro gets a private apt
# root (its own config, lists, cache and dpkg status) under the cache
# directory, and every install is simulated (apt-get -s). The base system is
# the distro's required and important packages plus its desktop, written
# into that root's dpkg status as if installed. Then, on top of it:
#
#   1. the ohmydebn package, as install.sh installs it
#   2. the optional packages from dependencies.sh and power-user.sh, the
#      way ohmydebn-pkg-install-optional installs them (those the distro
#      lacks are skipped there, so they're only listed here)
#   3. each bin/*-install script's packages, on the system 1 and 2 leave
#
# An installer that adds a vendor's own apt repo or downloads a vendor .deb
# is listed but not checked: its packages aren't in the distro's archives.
# One whose package the distro doesn't have shows as n/a, not as a
# failure: some installers check for that and say so, but where one
# doesn't, its menu item ends in apt's "Unable to locate package" there.
#
# Needs the network: the first run downloads every distro's package lists
# (a few hundred MB, kept compressed in the cache directory) and later runs
# refresh them. Not part of tests/run.sh for that reason; run it before a
# release.
#
# Usage: tests/distro-checks.py [--stable] [--recommends] [distro...]
#   --stable      check against the stable OhMyDebn repo (default: testing)
#   --recommends  on distros with Recommends off, list each installer's
#                 direct Recommends that won't be installed there
#   distro...     only these (default: all; --list shows the names)

import os
import re
import shutil
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "ohmydebn-distro-checks")

DEBIAN = [
    "deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware",
    "deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware",
    "deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware",
]
DEVUAN = [
    "deb http://deb.devuan.org/merged excalibur main contrib non-free non-free-firmware",
    "deb http://deb.devuan.org/merged excalibur-updates main contrib non-free non-free-firmware",
    "deb http://deb.devuan.org/merged excalibur-security main contrib non-free non-free-firmware",
]


def ubuntu(codename, mirror="http://archive.ubuntu.com/ubuntu", security="http://security.ubuntu.com/ubuntu"):
    parts = "main restricted universe multiverse"
    return [
        f"deb {mirror} {codename} {parts}",
        f"deb {mirror} {codename}-updates {parts}",
        f"deb {mirror} {codename}-backports {parts}",
        f"deb {security} {codename}-security {parts}",
    ]


MINT_PIN = [("packages.linuxmint.com", 700)]

# Zorin OS isn't here: its own repos publish empty package lists (they're
# only filled in for Zorin's installs), so from outside it's Ubuntu 24.04,
# which ubuntu-noble covers.
#
# Each distro as a fresh install leaves it: its apt sources, the pins it
# ships, its architecture, whether apt installs Recommends, the packages
# beyond required and important that make up its desktop, and any
# required or important ones it doesn't install. The
# desktop matters: it's what an install has to fit around (LCOS's
# XLibre X server, Mint's Cinnamon, Ubuntu's GNOME).
DISTROS = {
    "debian": dict(sources=DEBIAN, base=["xorg", "task-desktop"]),
    # MX 25 installs both inits through its init-diversity packages, which
    # conflict with Debian's systemd-sysv.
    "mx": dict(sources=DEBIAN + ["deb http://mxrepo.com/mx/repo trixie main non-free"],
               recommends=False, base=["init-default-mx-systemd", "xorg", "mx-system", "mx-apps"],
               exclude=["systemd-sysv"]),
    "devuan": dict(sources=DEVUAN, base=["xorg", "task-desktop"]),
    # XLibre in place of Xorg: lcos-desktop accepts either, and left to
    # itself apt picks Devuan's Xorg. Plymouth, which lcos-desktop brings,
    # conflicts with Devuan's bootlogd.
    "lcos": dict(sources=DEVUAN + ["deb https://lcos.lunduke.com/apt excalibur main"],
                 recommends=False, base=["lcos-base", "lcos-desktop", "xlibre"], exclude=["bootlogd"]),
    "lmde": dict(sources=DEBIAN + ["deb http://packages.linuxmint.com gigi main upstream import backport"],
                 pins=MINT_PIN, base=["xorg", "mint-meta-cinnamon"]),
    "mint": dict(sources=ubuntu("noble") + ["deb http://packages.linuxmint.com zena main upstream import backport"],
                 pins=MINT_PIN, base=["mint-meta-cinnamon"]),
    "ubuntu-noble": dict(sources=ubuntu("noble"), base=["ubuntu-desktop-minimal"]),
    "ubuntu-resolute": dict(sources=ubuntu("resolute"), base=["ubuntu-desktop-minimal"]),
    "pop": dict(sources=ubuntu("noble", "http://apt.pop-os.org/ubuntu", "http://apt.pop-os.org/ubuntu")
                + ["deb http://apt.pop-os.org/release noble main",
                   "deb http://apt.pop-os.org/proprietary noble main"],
                pins=[("apt.pop-os.org/release", 1001)], base=["pop-desktop"]),
    "kali": dict(sources=["deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware"],
                 base=["kali-desktop-xfce"]),
    "parrot": dict(sources=[f"deb https://deb.parrot.sh/parrot {s} main contrib non-free non-free-firmware"
                            for s in ("echo", "echo-security", "echo-backports")],
                   base=["parrot-desktop-mate"]),
    "rpios": dict(sources=DEBIAN + ["deb http://archive.raspberrypi.com/debian trixie main"],
                  arch="arm64", base=["rpd-wayland-core"]),
}

# Failures already known and written up, so a release run doesn't stop on
# them. Each says where. Take an entry out when its fix lands.
KNOWN = {
    ("lcos", "remote-desktop-server"): "XLibre can't take xorgxrdp; see TODO.md",
}

# Installers whose apt line names its packages through a variable: what
# each one can ask for. "a|b" is the first of them the distro has, "a?" is
# only when the distro has it (both as the installer decides at runtime).
COMPUTED = {
    "chromium": ["chromium|chromium-browser"],
    "docker": ["docker.io", "docker-cli?"],
    "virtmanager": ["qemu-system-x86|qemu-system-arm", "virt-manager", "virt-viewer", "libvirt-daemon-system",
                    "libvirt-clients", "bridge-utils", "ovmf?", "passt"],
}
# Read from these scripts' PACKAGES=(...) lines rather than copied here.
COMPUTED_FROM = {"uxplay": "bin/ohmydebn-uxplay-installed", "podman": "bin/ohmydebn-podman-installed"}
# Not installers of an app: the generic installer behind Install > Package.
NOT_APPS = {"pkg"}


def run(args, env=None):
    return subprocess.run(args, env=env, capture_output=True, text=True)


class Root:
    """A private apt root for one distro."""

    def __init__(self, name, cfg, ohmydebn_repo):
        self.name = name
        self.dir = os.path.join(CACHE, name)
        self.arch = cfg.get("arch", "amd64")
        self.recommends = cfg.get("recommends", True)
        self.status = os.path.join(self.dir, "var/lib/dpkg/status")
        for d in ("etc/apt/sources.list.d", "etc/apt/preferences.d", "etc/apt/apt.conf.d", "etc/apt/trusted.gpg.d",
                  "var/lib/apt/lists/partial", "var/cache/apt/archives/partial", "var/lib/dpkg", "log"):
            os.makedirs(os.path.join(self.dir, d), exist_ok=True)
        open(self.status, "w").close()
        conf = os.path.join(self.dir, "apt.conf")
        with open(conf, "w") as f:
            f.write(f'''Dir "{self.dir}/";
Dir::State "var/lib/apt/";
Dir::State::status "{self.status}";
Dir::Cache "var/cache/apt/";
Dir::Etc "etc/apt/";
Dir::Log "log/";
Debug::NoLocking "1";
APT::Architecture "{self.arch}";
APT::Architectures {{ "{self.arch}"; }};
Acquire::Languages "none";
Acquire::GzipIndexes "true";
Acquire::CompressionTypes::Order {{ "gz"; }};
Acquire::IndexTargets::deb::Contents-deb::DefaultEnabled "false";
Acquire::IndexTargets::deb::DEP-11::DefaultEnabled "false";
Acquire::IndexTargets::deb::DEP-11-icons::DefaultEnabled "false";
Acquire::IndexTargets::deb::DEP-11-icons-hidpi::DefaultEnabled "false";
Acquire::IndexTargets::deb::CNF::DefaultEnabled "false";
APT::Sandbox::User "{os.environ.get("USER") or run(["id", "-un"]).stdout.strip()}";
APT::Install-Recommends "{"true" if self.recommends else "false"}";
''')
        self.env = dict(os.environ, APT_CONFIG=conf, LC_ALL="C")
        # trusted=yes: only package lists are downloaded, never a package,
        # and nothing here is installed, so the distros' keyrings (which
        # this machine mostly doesn't have) aren't needed.
        lines = [re.sub(r"^deb ", "deb [trusted=yes] ", s) for s in cfg["sources"]]
        lines.append(f"deb [trusted=yes] {ohmydebn_repo} trixie main")
        with open(os.path.join(self.dir, "etc/apt/sources.list"), "w") as f:
            f.write("\n".join(lines) + "\n")
        with open(os.path.join(self.dir, "etc/apt/preferences.d/distro.pref"), "w") as f:
            for origin, prio in cfg.get("pins", []):
                f.write(f"Package: *\nPin: origin {origin.split('/')[0]}\nPin-Priority: {prio}\n\n")

    def apt_get(self, *args):
        return run(["apt-get", "-q", *args], self.env)

    def simulate(self, pkgs, recommends=None):
        """apt-get -s install; returns (ok, output)."""
        opts = []
        if recommends is not None:
            opts = ["-o", f"APT::Install-Recommends={'true' if recommends else 'false'}"]
        r = self.apt_get("-s", *opts, "install", *pkgs)
        return r.returncode == 0, r.stdout + r.stderr

    def available(self):
        """({every real package the distro offers for this arch}, {those
        of priority required or important}). Real: not just a name some
        other package mentions."""
        names, base = set(), set()
        for st in run(["apt-cache", "dumpavail"], self.env).stdout.split("\n\n"):
            if st.startswith("Package: "):
                pkg = st.split("\n", 1)[0][9:]
                names.add(pkg)
                if re.search(r"^Priority: (required|important)$", st, re.M):
                    base.add(pkg)
        return names, base

    def install_state(self, sim_output):
        """Writes the packages a simulated install would install into this
        root's dpkg status, as installed."""
        want = re.findall(r"^Inst (\S+) (?:\[\S+\] )?\((\S+) ", sim_output, re.M)
        current = {}
        if os.path.getsize(self.status):
            for st in open(self.status).read().split("\n\n"):
                if st.startswith("Package: "):
                    current[st.split("\n", 1)[0][9:]] = st
        for pkg in removals(sim_output):
            current.pop(pkg, None)
        r = run(["apt-cache", "show", *[f"{p}={v}" for p, v in want]], self.env) if want else None
        drop = ("Filename", "Size", "MD5sum", "SHA1", "SHA256", "SHA512", "Description-md5", "Task",
                "Supported", "Origin", "Bugs")
        seen = set()
        for st in (r.stdout if r else "").split("\n\n"):
            if not st.startswith("Package: "):
                continue
            lines = st.splitlines()
            pkg = lines[0][9:]
            if pkg in seen:
                continue
            seen.add(pkg)
            kept, skip = [], False
            for line in lines:
                if not line.startswith(" "):
                    skip = line.split(":", 1)[0] in drop
                if not skip:
                    kept.append(line)
            kept.insert(1, "Status: install ok installed")
            current[pkg] = "\n".join(kept)
        with open(self.status, "w") as f:
            f.write("\n\n".join(current.values()) + "\n\n")
        return len(seen)


def unmet(output, limit=4):
    """The lines of apt's output that say why an install can't work."""
    lines = [line.strip() for line in output.splitlines()
             if re.search(r"Depends:|Conflicts:|Breaks:|PreDepends:|^E: ", line)
             and "Unable to correct problems" not in line and "Unmet dependencies" not in line]
    return lines[:limit] or [output.strip().splitlines()[-1] if output.strip() else "apt failed"]


def removals(output):
    return re.findall(r"^Remv (\S+)", output, re.M)


def array_from(path, name="PACKAGES"):
    # To the ")" alone on a line, or on the same line: comments inside
    # can hold parentheses of their own.
    text = open(os.path.join(REPO_ROOT, path)).read()
    m = re.search(rf"^{name}=\((.*?)^\)", text, re.M | re.S) or re.search(rf"^{name}=\(([^)]*)\)", text, re.M)
    return re.sub(r"#.*", "", m.group(1)).split() if m else []


def power_user_packages():
    text = open(os.path.join(REPO_ROOT, "install/packaging/power-user.sh")).read()
    m = re.search(r"ohmydebn-pkg-install-optional((?:[^|]|\|(?!\|))*)\|\|", text)
    return m.group(1).replace("\\\n", " ").split() if m else []


def installers():
    """{name: (packages, flags) or "vendor"} for every bin/*-install."""
    found = {}
    bindir = os.path.join(REPO_ROOT, "bin")
    for f in sorted(os.listdir(bindir)):
        m = re.fullmatch(r"ohmydebn-(.+)-install", f)
        if not m or m.group(1) in NOT_APPS:
            continue
        name = m.group(1)
        text = open(os.path.join(bindir, f)).read()
        if re.search(r"preferences\.d|ohmydebn-apt-install-deb|ohmydebn-[a-z-]+-repo\b", text):
            found[name] = "vendor"
            continue
        pkgs, flags = [], []
        for line in text.splitlines():
            if line.lstrip().startswith("#"):
                continue
            m = re.search(r"/usr/bin/apt (.*?)(?<![-\w])install(?![-\w])(.*)", line)
            if not m:
                continue
            flags += [x for x in m.group(1).split() if x.startswith("--")]
            rest = re.split(r";|\|\||&&|\bthen\b", m.group(2))[0].split()
            flags += [x for x in rest if x.startswith("--")]
            pkgs += [x.strip('"') for x in rest if not x.startswith("-")]
        if any("$" in p for p in pkgs):
            if name in COMPUTED:
                pkgs = COMPUTED[name]
            elif name in COMPUTED_FROM:
                pkgs = array_from(COMPUTED_FROM[name])
            else:
                pkgs = None  # reported: this script needs a COMPUTED entry
        if pkgs:  # the rest install no app (theme, webapp...)
            found[name] = (pkgs, flags)
    return found


def pick(spec, available):
    """A COMPUTED-style package spec to the name the installer would use,
    or None when the distro has none of it (and "" when it's optional)."""
    optional = spec.endswith("?")
    for alt in spec.rstrip("?").split("|"):
        if alt in available:
            return alt
    return "" if optional else None


class Report:
    def __init__(self):
        self.failures = 0

    def line(self, tag, text):
        print(f"  {tag:<5} {text}")

    def fail(self, text, why=()):
        self.failures += 1
        self.line("FAIL", text)
        for w in why:
            print(f"          {w}")


def check(name, cfg, repo, report, show_recommends):
    print(f"\n== {name} ({cfg.get('arch', 'amd64')}, Recommends {'on' if cfg.get('recommends', True) else 'off'})")
    root = Root(name, cfg, repo)
    r = root.apt_get("update")
    if r.returncode != 0 or re.search(r"^(E|W): Failed to fetch", r.stdout + r.stderr, re.M):
        report.fail("couldn't download the package lists", unmet(r.stdout + r.stderr))
        return
    available, base = root.available()

    # The base system: required and important, plus the desktop.
    missing = [p for p in cfg["base"] if p not in available]
    if missing:
        report.fail(f"base system: this script's desktop package isn't in {name}: {' '.join(missing)}")
        return
    ok, out = root.simulate(sorted(base - set(cfg.get("exclude", []))) + cfg["base"])
    if not ok:
        report.fail("base system can't be simulated (fix DISTROS in this script)", unmet(out))
        return
    report.line("ok", f"base system ({root.install_state(out)} packages)")

    # 1. The ohmydebn package, as install.sh installs it.
    ok, out = root.simulate(["ohmydebn", "dbus-x11"])
    if not ok:
        report.fail("ohmydebn package can't be installed", unmet(out))
        return
    gone = removals(out)
    report.line("ok", "ohmydebn package" + (f" (removes {' '.join(gone)})" if gone else ""))
    root.install_state(out)

    # 2. The optional packages, which ohmydebn-pkg-install-optional installs
    # without Recommends, skipping those the distro doesn't have.
    wanted = array_from("install/packaging/dependencies.sh") + power_user_packages()
    have = [p for p in wanted if p in available]
    lacking = [p for p in wanted if p not in available]
    ok, out = root.simulate(have, recommends=False)
    if ok:
        root.install_state(out)
        gone = removals(out)
        report.line("ok", f"optional packages ({len(have)} of {len(wanted)})"
                    + (f", removes {' '.join(gone)}" if gone else ""))
    else:
        # The real install falls back to one package at a time; find which.
        bad = [p for p in have if not root.simulate([p], recommends=False)[0]]
        report.fail(f"optional packages don't install together; alone, these fail: {' '.join(bad) or '(none)'}",
                    unmet(out))
    if lacking:
        report.line("info", f"optional packages {name} doesn't have: {' '.join(lacking)}")

    # spice-vdagent.sh installs this exact version in VMs with a SPICE display.
    ok, out = root.simulate(["spice-vdagent=0.22.1-4.1"])
    if not ok:
        report.fail("spice-vdagent 0.22.1-4.1 (installed in VMs with SPICE)", unmet(out))

    # 3. Each installer, on the system above.
    vendor, passed = [], []
    for app, spec in installers().items():
        if spec == "vendor":
            vendor.append(app)
            continue
        pkgs, flags = spec
        if pkgs is None:
            report.fail(f"{app}: its apt line uses a variable; add it to COMPUTED in this script")
            continue
        chosen = [pick(p, available) for p in pkgs]
        if None in chosen:
            gone = [p for p, c in zip(pkgs, chosen) if c is None]
            report.line("n/a", f"{app}: {name} doesn't have {' '.join(gone)}")
            continue
        chosen = [c for c in chosen if c]
        recommends = False if "--no-install-recommends" in flags else True if "--install-recommends" in flags else None
        ok, out = root.simulate(chosen, recommends)
        # Removing anything to make room counts as failing: apt would take
        # out part of the desktop (or refuse, as apt on LCOS does).
        gone = removals(out) if ok else []
        problem = unmet(out) if not ok else [f"removes {' '.join(gone)}"] if gone else None
        known = KNOWN.get((name, app))
        if problem and known:
            report.line("known", f"{app}: {known}")
        elif problem:
            report.fail(f"{app}: {' '.join(chosen)}", problem)
        elif known:
            report.fail(f"{app}: installs now; take it out of KNOWN in this script")
        else:
            passed.append(app)
        if show_recommends and not root.recommends and recommends is None:
            skipped = recommends_left_out(root, chosen)
            if skipped:
                report.line("info", f"{app}: Recommends left out here: {' '.join(skipped)}")
    report.line("ok", f"installers: {' '.join(passed)}")
    report.line("skip", f"vendor repos, not checked: {' '.join(vendor)}")


def recommends_left_out(root, pkgs):
    """The named packages' direct Recommends that installing them here
    (Recommends off) leaves out, but Recommends on would install."""
    _, off = root.simulate(pkgs)
    _, on = root.simulate(pkgs, recommends=True)
    extra = set(re.findall(r"^Inst (\S+)", on, re.M)) - set(re.findall(r"^Inst (\S+)", off, re.M))
    r = run(["apt-cache", "depends", "--no-pre-depends", "--no-depends", "--no-suggests", "--no-conflicts",
             "--no-breaks", "--no-replaces", "--no-enhances", *pkgs], root.env)
    direct = set(re.findall(r"^\s+Recommends: <?([^>\s]+)", r.stdout, re.M))
    return sorted(direct & extra)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    opts = {a for a in argv if a.startswith("--")}
    if "--list" in opts:
        print(" ".join(DISTROS))
        return 0
    unknown = [a for a in args if a not in DISTROS]
    bad_opts = opts - {"--stable", "--recommends"}
    if unknown or bad_opts:
        print(f"unknown: {' '.join(unknown + sorted(bad_opts))} (distros: {' '.join(DISTROS)})", file=sys.stderr)
        return 2
    if not shutil.which("apt-get"):
        print("apt-get not available - skipping (not a Debian-family system)")
        return 0
    repo = "https://packages.ohmydebn.org" if "--stable" in opts else "https://packages-testing.ohmydebn.org"
    print(f"=== distro-checks (OhMyDebn repo: {repo}) ===")
    report = Report()
    for name in args or DISTROS:
        check(name, DISTROS[name], repo, report, "--recommends" in opts)
    print(f"\n{report.failures} failure(s)")
    return 1 if report.failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
