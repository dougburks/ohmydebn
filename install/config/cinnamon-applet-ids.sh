#!/bin/bash

# Panels seeded before 4.10.0 gave two pairs of applets the same instance
# ID (network and the workspace switcher both 10, the window list and
# power both 12), so removing one could leave it on the panel until
# Cinnamon restarted. ohmydebn-cinnamon-applet-ids renumbers the duplicates
# (and moves a renumbered multi-instance applet's settings file with it).
# It changes nothing once the IDs are unique, so no marker is needed; the
# dry run decides whether there's anything to announce. The running
# Cinnamon keeps showing a renumbered applet under its old ID as well (two
# network icons, say) until it restarts, so finalization/finale.sh restarts
# it at the end of the run.
APPLET_ID_CHANGES=$(/usr/share/ohmydebn/bin/ohmydebn-cinnamon-applet-ids --dry-run || true)
if [ -n "$APPLET_ID_CHANGES" ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Giving each panel applet its own ID"
  if /usr/share/ohmydebn/bin/ohmydebn-cinnamon-applet-ids; then
    export OHMYDEBN_CINNAMON_RESTART_NEEDED=1
  fi
fi
