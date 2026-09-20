#!/bin/bash

# Warm ohmydebn-theme-carousel's disk cache for every installed theme at
# this display's monitor sizes, so the first carousel launch on a new
# machine (or after a theme update) shows pictures instead of empty
# frames while it decodes each wallpaper. Runs after updates.sh, since
# that's what upgrades the theme packages (new files, new cache keys).
# Detached and at the lowest CPU and I/O priority: it takes some tens of
# seconds on a cold machine and nothing in the install waits for it -
# the carousel itself warms whatever's still missing the first time it
# opens. Needs a display to size for; a headless run (no DISPLAY) has no
# monitor to warm for and skips.
if [ -n "${DISPLAY:-}" ] && [ -x /usr/share/ohmydebn/bin/ohmydebn-theme-carousel ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Preparing theme previews in the background"
  setsid nice -n 19 ionice -c 3 /usr/share/ohmydebn/bin/ohmydebn-theme-carousel --warm-cache >/dev/null 2>&1 &
fi
