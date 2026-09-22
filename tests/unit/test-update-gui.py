#!/usr/bin/python3
#
# Pure-logic regression tests for ohmydebn-update-gui: the pty stream
# parser (StreamWatcher) that turns raw update output into stage/
# sudo-prompt events, exit-code normalization, and version reading.
# Importing the script is safe with no DISPLAY set - module-level code
# only defines classes and constants (main() is guarded), same reasoning
# as test-speedtest-guis.py's own header. It's also safe without
# gir1.2-vte-2.91 installed: the script wraps its VTE import in
# try/except specifically so old installs (and this test) can load it
# regardless - VTE_AVAILABLE just reads False there.

import os
import sys
import tempfile
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


def load(name):
    return SourceFileLoader(name, os.path.join(BIN, name)).load_module()


print("=== ohmydebn-update-gui (pure logic) ===")
gui = load("ohmydebn-update-gui")

FENCE = "#" * 68


def feed_all(watcher, chunks):
    events = []
    for chunk in chunks:
        events += watcher.feed(chunk)
    return events


# A complete ohmydebn-headline banner (fence, title, fence, blank - the
# exact shape bin/ohmydebn-headline prints) becomes one stage event.
w = gui.StreamWatcher()
events = feed_all(w, [f"\n{FENCE}\nConfiguring Alacritty\n{FENCE}\n\n"])
check_eq("headline banner emits one stage event", events, [("stage", "Configuring Alacritty")])

# The same banner arriving split across arbitrary chunk boundaries
# (including mid-fence and mid-title) parses identically - pty reads are
# chunked wherever the kernel feels like it.
w = gui.StreamWatcher()
banner = f"\n{FENCE}\nConfiguring Alacritty\n{FENCE}\n\n"
events = feed_all(w, [banner[i : i + 7] for i in range(0, len(banner), 7)])
check_eq("banner split into 7-byte chunks still emits the stage", events, [("stage", "Configuring Alacritty")])

# Output following the closing fence must NOT read as a stage: headline
# always prints a blank line after the closing fence, and that blank
# resets the after-fence state.
w = gui.StreamWatcher()
events = feed_all(w, [f"{FENCE}\nReal Stage\n{FENCE}\n\napt output that is not a stage\n"])
check_eq("post-banner output is not a stage", events, [("stage", "Real Stage")])

# ANSI color/cursor sequences around the banner (a colored PS1, grc, apt
# progress styling) are stripped before matching.
w = gui.StreamWatcher()
events = feed_all(w, [f"\x1b[32m{FENCE}\x1b[0m\n\x1b[1mColored Stage\x1b[0m\n{FENCE}\n\n"])
check_eq("ANSI-wrapped banner still parses", events, [("stage", "Colored Stage")])

# \r-redrawn progress lines (curl/apt percentage bars) never look like
# stages, and \r\n line endings (pty onlcr) parse the same as \n.
w = gui.StreamWatcher()
events = feed_all(w, ["Progress:  10%\rProgress:  50%\rProgress: 100%\r\n", f"{FENCE}\r\nCRLF Stage\r\n{FENCE}\r\n\r\n"])
check_eq("\\r progress redraws emit nothing; CRLF banner parses", events, [("stage", "CRLF Stage")])

# A sudo prompt has no trailing newline - the marker must be detected in
# the unterminated line tail, and exactly once even as more of the same
# line trickles in afterward.
marker = gui.SUDO_PROMPT_MARKER
w = gui.StreamWatcher()
events = feed_all(w, [marker[: len(marker) // 2], marker[len(marker) // 2 :]])
check_eq("sudo marker split across chunks emits one prompt event", events, [("sudo-prompt",)])
check_eq("no duplicate event when the prompt line later completes", w.feed("\n"), [])

# A re-prompt after a wrong password is a NEW marker occurrence and must
# fire again - that's what re-opens the password dialog.
events = w.feed(f"Sorry, try again.\n{marker} ")
check_eq("second sudo prompt fires a second event", events, [("sudo-prompt",)])

# Interleaved full flow: banner, sudo prompt, then another banner - order
# preserved.
w = gui.StreamWatcher()
events = feed_all(
    w,
    [
        f"{FENCE}\nOhMyDebn Update - current OhMyDebn version: 4.6.0\n{FENCE}\n\n",
        f"{marker} ",
        f"\n{FENCE}\nChecking for an updated ohmydebn package\n{FENCE}\n\n",
    ],
)
check_eq(
    "full flow keeps event order",
    events,
    [
        ("stage", "OhMyDebn Update - current OhMyDebn version: 4.6.0"),
        ("sudo-prompt",),
        ("stage", "Checking for an updated ohmydebn package"),
    ],
)

# Nothing is auto-answered any more (see the CONSENT_PROMPT_MARKER
# comment in the GUI): the stock "Press Enter to continue or Ctrl-C to
# cancel." line - ohmydebn-update's own, and the identical prompt of some
# fifty ohmydebn-*-install/-remove scripts - must emit NO event, and so
# must ohmydebn-update-pause's "Press Enter to close this window".
w = gui.StreamWatcher()
check_eq(
    "stock capital-C Press Enter prompt emits nothing (no auto-answer)",
    w.feed("Press Enter to continue or Ctrl-C to cancel.\n"),
    [],
)
check("the retired auto-answer marker is gone", not hasattr(gui, "LEGACY_ENTER_PROMPT"))
check("the retired auto-answer handler is gone", not hasattr(gui.UpdateWindow, "_on_enter_prompt"))
w = gui.StreamWatcher()
check_eq(
    "update-pause's close-window prompt does NOT match",
    w.feed("Press Enter to close this window\n"),
    [],
)

# install.sh's own consent prompts (lowercase "Ctrl-c") emit a
# consent-prompt event - surfaced to the user, never auto-answered. Both
# real install.sh prompt shapes are covered: the warning form ("Press
# Enter if you are sure...") and the first-install welcome form.
w = gui.StreamWatcher()
check_eq(
    "install.sh root/distro warning emits consent-prompt",
    w.feed("Press Enter if you are sure you want to continue as root\nor Ctrl-c to cancel.\n"),
    [("consent-prompt",)],
)
w = gui.StreamWatcher()
check_eq(
    "install.sh welcome prompt emits consent-prompt",
    w.feed("Press Enter to continue or Ctrl-c to cancel.\n"),
    [("consent-prompt",)],
)
w = gui.StreamWatcher()
check_eq(
    "capital-C prompt does not read as a consent prompt either",
    w.feed("Press Enter to continue or Ctrl-C to cancel.\n"),
    [],
)

# is_fence: the real 68-char fence and a short 10-char one match; an
# ordinary comment, a blank line, and a hash-prefixed sentence don't.
check("is_fence: real 68-char fence", gui.is_fence(FENCE))
check("is_fence: minimal 10-char fence", gui.is_fence("#" * 10))
check("is_fence: 9 chars is too short (comments must not match)", not gui.is_fence("#" * 9))
check("is_fence: shell comment is not a fence", not gui.is_fence("# comment text"))
check("is_fence: blank line is not a fence", not gui.is_fence(""))

# normalize_returncode: subprocess's returncode shapes -> shell-style
# exit codes (negative = killed by that signal).
check_eq("normalize_returncode: clean exit passes through", gui.normalize_returncode(0), 0)
check_eq("normalize_returncode: real exit code passes through", gui.normalize_returncode(3), 3)
check_eq("normalize_returncode: SIGTERM (-15) reads as 143", gui.normalize_returncode(-15), 143)
check_eq("normalize_returncode: not-yet-exited (None) reads as failure", gui.normalize_returncode(None), 1)

# (Palette parsing/contrast tests moved to test-theme-colors.py when the
# loader moved into bin/ohmydebn_theme_colors.py.)

# read_version: reads $DIR/VERSION, trims, and degrades to "unknown"
# rather than raising - the version label must never take the window down.
with tempfile.TemporaryDirectory() as tmp:
    with open(os.path.join(tmp, "VERSION"), "w", encoding="utf-8") as f:
        f.write("4.6.0\n")
    check_eq("read_version: reads and trims VERSION", gui.read_version(tmp), "4.6.0")
    check_eq("read_version: missing file degrades to unknown", gui.read_version(os.path.join(tmp, "nope")), "unknown")
    with open(os.path.join(tmp, "VERSION"), "w", encoding="utf-8") as f:
        f.write("\n")
    check_eq("read_version: empty file degrades to unknown", gui.read_version(tmp), "unknown")

# The guarded() decorator is the window's no-crash contract: a callback
# that raises must log and return its declared default instead of letting
# the exception unwind into GTK's C main loop.
calls = []


@gui.guarded(default="fallback")
def boom():
    calls.append(1)
    raise RuntimeError("synthetic callback bug")


sys.stderr.write("(expected traceback follows - guarded() logs it by design)\n")
check_eq("guarded: exception becomes the declared default", boom(), "fallback")
check_eq("guarded: wrapped function actually ran", len(calls), 1)

print()

# --- abort escalation plan (see ABORT_ESCALATION's comment) ---
# The child's process group includes apt and dpkg. SIGINT (apt's graceful
# interrupt) first, SIGTERM after a grace period, and NEVER SIGKILL - a
# killed dpkg mid-configure is the inconsistent state the abort dialog
# warns about. Pinned here so a future "make abort faster" change can't
# quietly reintroduce it.
import signal as _signal  # noqa: E402

plan = list(gui.ABORT_ESCALATION)
check_eq("abort plan: opens with SIGINT immediately", plan[0], (0, _signal.SIGINT))
check_eq("abort plan: escalates to SIGTERM after a grace period", plan[1][1], _signal.SIGTERM)
check("abort plan: grace period is positive", plan[1][0] > 0)
check("abort plan: never SIGKILLs apt/dpkg", all(sig != _signal.SIGKILL for _d, sig in plan))
check("abort plan: delays are ascending", all(a[0] < b[0] for a, b in zip(plan, plan[1:])))
check("abort plan: patience wait comes after the last signal", gui.ABORT_PATIENCE_MS > plan[-1][0])


# --- single instance: the lock and the "present yourself" poke ---
# Exercised against a real second process, since that's the whole point:
# the lock must be held across processes, a stale lock file with no
# flock behind it must be taken over, and the holder must actually
# receive the SIGUSR1 that asks it to present its window.
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import signal as _sig  # noqa: E402

GUI_PATH = os.path.join(BIN, "ohmydebn-update-gui")
with tempfile.TemporaryDirectory() as tmp:
    lock_path = os.path.join(tmp, "instance.lock")

    fd, holder = gui.acquire_instance_lock(lock_path)
    check("lock: first acquire succeeds", fd is not None and holder is None)
    with open(lock_path, encoding="utf-8") as f:
        check_eq("lock: holder pid recorded", f.read().strip(), str(os.getpid()))

    # A second PROCESS trying the same lock must be refused and told our pid.
    # Same SourceFileLoader trick as load() above - the script has no .py
    # extension, so a spec-based import finds no loader for it.
    probe = (
        "from importlib.machinery import SourceFileLoader\n"
        f"gui = SourceFileLoader('gui', {GUI_PATH!r}).load_module()\n"
        f"fd, holder = gui.acquire_instance_lock({lock_path!r})\n"
        "print('acquired' if fd is not None else f'held-by {holder}')\n"
    )
    result = subprocess.run([sys.executable, "-c", probe], capture_output=True, text=True, check=False)
    check_eq("lock: a second process is refused and learns the holder's pid",
             result.stdout.strip(), f"held-by {os.getpid()}")

    # Same-process re-acquire is also refused (flock is per open file description).
    fd2, holder2 = gui.acquire_instance_lock(lock_path)
    check("lock: re-acquire while held is refused", fd2 is None and holder2 == os.getpid())

    # Releasing (closing the fd) frees it; a stale file with a dead pid and
    # no flock is simply taken over.
    os.close(fd)
    with open(lock_path, "w", encoding="utf-8") as f:
        f.write("999999999\n")
    fd3, holder3 = gui.acquire_instance_lock(lock_path)
    check("lock: stale lock file (no flock, dead pid) is taken over", fd3 is not None and holder3 is None)
    os.close(fd3)

    # present_existing_instance: the holder really gets SIGUSR1. A helper
    # process installs a handler that exits 42 on SIGUSR1, and we poke it.
    waiter = subprocess.Popen(
        [sys.executable, "-c",
         "import signal, sys, time\n"
         "signal.signal(signal.SIGUSR1, lambda *_: sys.exit(42))\n"
         "print('ready', flush=True)\n"
         "time.sleep(10)\n"],
        stdout=subprocess.PIPE, text=True,
    )
    waiter.stdout.readline()  # wait for 'ready' so the handler is installed
    check("present: signal delivered to a live holder", gui.present_existing_instance(waiter.pid))
    check_eq("present: the holder received SIGUSR1", waiter.wait(timeout=5), 42)
    check("present: no pid means nothing to poke", not gui.present_existing_instance(None))
    check("present: a dead pid is reported as not delivered", not gui.present_existing_instance(999999999))

# instance_lock_path honors XDG_RUNTIME_DIR and falls back to /tmp.
saved = os.environ.get("XDG_RUNTIME_DIR")
try:
    with tempfile.TemporaryDirectory() as tmp:
        os.environ["XDG_RUNTIME_DIR"] = tmp
        check_eq("lock path: under XDG_RUNTIME_DIR, per uid",
                 gui.instance_lock_path(), os.path.join(tmp, f"ohmydebn-update-gui-{os.getuid()}.lock"))
    os.environ["XDG_RUNTIME_DIR"] = "/definitely/not/a/dir"
    check_eq("lock path: falls back to /tmp when the runtime dir is unusable",
             gui.instance_lock_path(), f"/tmp/ohmydebn-update-gui-{os.getuid()}.lock")
finally:
    if saved is None:
        os.environ.pop("XDG_RUNTIME_DIR", None)
    else:
        os.environ["XDG_RUNTIME_DIR"] = saved


# --- pre-flight release check: parsing, ordering, wording, and the fetch ---
check_eq("parse_latest_tag: strips the v prefix", gui.parse_latest_tag('{"tag_name": "v4.8.0"}'), "4.8.0")
check_eq("parse_latest_tag: bare tag passes through", gui.parse_latest_tag('{"tag_name": "4.8.0"}'), "4.8.0")
check("parse_latest_tag: missing tag_name is None", gui.parse_latest_tag('{"name": "x"}') is None)
check("parse_latest_tag: empty tag is None", gui.parse_latest_tag('{"tag_name": "  "}') is None)
check("parse_latest_tag: invalid JSON is None", gui.parse_latest_tag("<html>rate limited</html>") is None)
check("parse_latest_tag: non-object JSON is None", gui.parse_latest_tag("[1, 2]") is None)

check("version_key: 4.8.0 > 4.7.0", gui.version_key("4.8.0") > gui.version_key("4.7.0"))
check("version_key: 4.10.0 > 4.9.0 (numeric, not lexical)", gui.version_key("4.10.0") > gui.version_key("4.9.0"))
check("version_key: equal versions compare equal", gui.version_key("4.8.0") == gui.version_key("4.8.0"))
check("version_key: a -rc1 suffix sorts after the bare version (as sort -V does)",
      gui.version_key("4.8.0-rc1") > gui.version_key("4.8.0"))
check("version_key: 5.0.0 > 4.99.99", gui.version_key("5.0.0") > gui.version_key("4.99.99"))

check_eq("preflight: newer release -> available",
         gui.preflight_message("4.7.0", "4.8.0"), ("OhMyDebn 4.8.0 is available.", "available"))
check_eq("preflight: same release -> current, and says OS packages still update",
         gui.preflight_message("4.8.0", "4.8.0")[1], "current")
check("preflight: same release wording mentions OS packages",
      "OS packages" in gui.preflight_message("4.8.0", "4.8.0")[0])
check_eq("preflight: dev build ahead of the release -> ahead",
         gui.preflight_message("4.9.0", "4.8.0")[1], "ahead")
check_eq("preflight: fetch failed -> unknown, update still offered",
         gui.preflight_message("4.8.0", None)[1], "unknown")
check_eq("preflight: unknown current version -> unknown",
         gui.preflight_message("unknown", "4.8.0")[1], "unknown")

# fetch_latest_release against a local HTTP server: a good answer, a
# non-JSON answer (GitHub's rate-limit HTML), and a refused connection.
import http.server  # noqa: E402
import socket  # noqa: E402
import threading  # noqa: E402


class _Releases(http.server.BaseHTTPRequestHandler):
    payload = b'{"tag_name": "v4.8.0"}'

    def do_GET(self):  # noqa: N802 - http.server API
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(self.payload)

    def log_message(self, *_args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), _Releases)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{server.server_port}"
check_eq("fetch: parses a good release answer", gui.fetch_latest_release(base + "/latest", timeout=3), "4.8.0")
_Releases.payload = b"<html>API rate limit exceeded</html>"
check("fetch: a non-JSON answer is None", gui.fetch_latest_release(base + "/latest", timeout=3) is None)
server.shutdown()
server.server_close()
with socket.socket() as probe_sock:
    probe_sock.bind(("127.0.0.1", 0))
    closed_port = probe_sock.getsockname()[1]
check("fetch: a refused connection is None, not an exception",
      gui.fetch_latest_release(f"http://127.0.0.1:{closed_port}/latest", timeout=3) is None)


# --- success status: a reboot-notice stage changes the final line ---
check_eq("success_message: plain run says up to date",
         gui.success_message(["Installing any available package updates", "OhMyDebn update complete - version: 4.8.0"]),
         "Update complete - you're up to date.")
check_eq("success_message: a reboot-notice stage asks for a reboot",
         gui.success_message(["OhMyDebn update complete - version: 4.8.0", gui.REBOOT_HEADLINE]),
         "Update complete - reboot when convenient to finish it.")
check_eq("success_message: no stages at all still reads as up to date", gui.success_message([]),
         "Update complete - you're up to date.")


# --- the real ohmydebn-headline output parses as exactly one stage, titled by
# the title line - pinned so a future change to the banner (a timestamp line
# inside it was tried once) can't break the GUI's stage parsing unnoticed ---
import subprocess as _sp  # noqa: E402
real_banner = _sp.run([os.path.join(BIN, "ohmydebn-headline"), "Configuring Alacritty"],
                      capture_output=True, text=True, check=False, env={k: v for k, v in os.environ.items() if k != "OHMYDEBN_RUN_START"}).stdout
w = gui.StreamWatcher()
check_eq("real banner: one stage event, the bare title", w.feed(real_banner), [("stage", "Configuring Alacritty")])

print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
