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

print(f"{TESTS_RUN - TESTS_FAILED}/{TESTS_RUN} passed")
sys.exit(1 if TESTS_FAILED else 0)
