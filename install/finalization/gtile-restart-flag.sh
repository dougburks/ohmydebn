#!/bin/bash

# Cinnamon loads an extension's JS into the already-running process -
# upgrading the ohmydebn-gtile package on disk does nothing to a session
# that's already running until Cinnamon reloads it, and (unlike newly
# *enabling* an extension, which Cinnamon picks up live via its own
# gsettings watcher) an in-place code upgrade of an already-enabled
# extension is not picked up automatically. Track the last version we
# restarted Cinnamon for and restart again only when that's changed - not
# on every run - and only if gTile is actually enabled, so a user who's
# turned it off doesn't get an unasked-for restart.
#
# This must run *after* finalization/updates.sh (which is what actually
# runs `apt upgrade`), not from install/config/cinnamon.sh - config/all.sh
# runs before finalization/all.sh in ohmydebn.sh's own
# packaging -> config -> cleanup -> finalization order, so checking the
# installed version there would see the OLD version: both a stale
# "out of date" warning (see the GTILE_MIN_VERSION check below - it used
# to live in cinnamon.sh too) and (confirmed live) restarting Cinnamon
# before ohmydebn-gtile had actually been upgraded that run.
#
# Doesn't restart Cinnamon directly - finalization/hotkeys.sh (sourced
# right after this) can also decide a restart is needed, for its own
# unrelated reason (updated keybindings). Two independent, backgrounded
# `cinnamon --replace &` calls in the same run would race each other -
# whichever finishes second effectively cancels the first mid-restart.
# Instead this just sets OHMYDEBN_CINNAMON_RESTART_NEEDED, a plain shell
# variable shared across every finalization script sourced into this same
# process (see ohmydebn.sh/all.sh) - finalization/finale.sh, the last
# step, does the one actual restart at the very end if anything asked for
# it.

GTILE_INSTALLED_VERSION=$(dpkg-query -W -f='${Version}' ohmydebn-gtile 2>/dev/null)

# Purely a diagnostic nudge, not a safety gate - an ohmydebn-gtile older
# than GTILE_MIN_VERSION has no code path that reads tile-rules.json at
# all, so apps just silently won't auto-tile on an out-of-date extension
# without this warning telling the user why.
GTILE_MIN_VERSION="2.3.1"
if [ -z "$GTILE_INSTALLED_VERSION" ] || ! dpkg --compare-versions "$GTILE_INSTALLED_VERSION" ge "$GTILE_MIN_VERSION"; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "WARNING: ohmydebn-gtile is out of date"
  echo "Installed: ${GTILE_INSTALLED_VERSION:-none}, need >= $GTILE_MIN_VERSION - apps launched via hotkeys/menu won't auto-tile until it's upgraded."
  echo "Run: sudo apt install --only-upgrade ohmydebn-gtile"
fi

if [ -n "$GTILE_INSTALLED_VERSION" ] && gsettings get org.cinnamon enabled-extensions 2>/dev/null | grep -q "gTile@OhMyDebn"; then
  GTILE_RESTART_STATE=~/.local/state/ohmydebn-config/gtile-cinnamon-restart-version
  GTILE_LAST_RESTARTED_VERSION=""
  [ -f "$GTILE_RESTART_STATE" ] && GTILE_LAST_RESTARTED_VERSION=$(cat "$GTILE_RESTART_STATE")
  if [ "$GTILE_INSTALLED_VERSION" != "$GTILE_LAST_RESTARTED_VERSION" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Cinnamon will restart at the end of this update for gtile"
    mkdir -p ~/.local/state/ohmydebn-config
    echo "$GTILE_INSTALLED_VERSION" > "$GTILE_RESTART_STATE"
    export OHMYDEBN_CINNAMON_RESTART_NEEDED=1
  fi
fi
