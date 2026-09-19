#!/usr/bin/python3
#
# Profiles bin/ohmydebn-theme-carousel on the live desktop: loads the
# script as a module, builds the Carousel, records time-to-first-draw,
# performs N Right moves back to back (the worst case - no pause for the
# prefetch thread to get ahead), then quits and prints the wall-clock
# numbers plus cProfile's top entries. NOT part of tests/run.sh - it opens
# the real full-screen carousel for a few seconds, so run it by hand:
#
#   tests/perf/profile-theme-carousel.py warm [moves]   # the real ~/.cache
#   tests/perf/profile-theme-carousel.py cold [moves]   # an empty scratch cache
#
# "cold" points CAROUSEL_CACHE_DIR at a fresh temp dir (the real cache is
# never touched), so it measures a first-ever launch: that's where decode
# cost lives. The stable metric across runs is the _decode_at_scale call
# count and its tottime - per-move milliseconds vary with thread
# scheduling and page cache state, so compare those with care. Numbers
# from the session that added the shared master decode (2540x1314, six
# rapid moves, cold cache): decodes 81 -> 45 -> 40 with the hybrid floor,
# decode CPU 2.0s -> 1.0s, sum of six moves 1.19s -> 0.73s, first draw
# unchanged (~400ms); warm moves 14-41ms -> 10-33ms after monitor
# geometry stopped being re-queried per keypress. After every decode moved
# to the DecodeWorker (two threads, per-slot want keys): input-blocked per
# move 82-177ms -> 2-5ms cold and 8-42ms -> ~2ms warm (the first move
# still pays ~35ms for the accent CSS reload), first draw 379ms -> ~100ms
# cold and 133ms -> 84ms warm, cold decodes 40 -> 24 (superseded jobs
# skipped), and "settled" - every image render() asked for on screen -
# 160-300ms per cold move.

import cProfile
import io
import os
import pstats
import sys
import tempfile
import time
from importlib.machinery import SourceFileLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
mode = sys.argv[1] if len(sys.argv) > 1 else "warm"
moves = int(sys.argv[2]) if len(sys.argv) > 2 else 6

t0 = time.monotonic()
tc = SourceFileLoader("tc", os.path.join(REPO_ROOT, "bin", "ohmydebn-theme-carousel")).load_module()
t_import = time.monotonic() - t0
if mode == "cold":
    tc.CAROUSEL_CACHE_DIR = tempfile.mkdtemp(prefix="carousel-cold-")
from gi.repository import GLib, Gtk  # noqa: E402

prof = cProfile.Profile()
prof.enable()
t1 = time.monotonic()
win = tc.Carousel()
t_construct = time.monotonic() - t1
first_draw = {}
move_times = []


settle_times = []


def do_moves():
    # Two numbers per move since decodes left the main thread: how long
    # move() blocks input (the keypress-to-caption latency), and how long
    # until every image render() asked for is on screen (pending_images()
    # reaches zero with the main loop drained).
    for _ in range(moves):
        s = time.monotonic()
        win.move(1)
        while Gtk.events_pending():
            Gtk.main_iteration()
        move_times.append(time.monotonic() - s)
        while win.pending_images() or Gtk.events_pending():
            Gtk.main_iteration_do(False)
            time.sleep(0.001)
        settle_times.append(time.monotonic() - s)
    GLib.timeout_add(300, lambda: (Gtk.main_quit(), False)[1])
    return False


def on_draw(*_):
    if "t" not in first_draw:
        first_draw["t"] = time.monotonic() - t1
        GLib.timeout_add(400, do_moves)
    return False


win.connect("draw", on_draw)
win.show_all()
win.fullscreen()
Gtk.main()
prof.disable()

print(f"[{mode}] import {t_import * 1000:.0f} ms, construct {t_construct * 1000:.0f} ms, "
      f"first draw {first_draw.get('t', 0) * 1000:.0f} ms after construct start")
print(f"[{mode}] per-move input-blocked ms: " + " ".join(f"{m * 1000:.0f}" for m in move_times))
print(f"[{mode}] per-move settled ms:       " + " ".join(f"{m * 1000:.0f}" for m in settle_times))
out = io.StringIO()
pstats.Stats(prof, stream=out).sort_stats("cumulative").print_stats(20)
print(out.getvalue())
