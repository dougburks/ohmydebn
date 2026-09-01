#!/bin/bash

# One consolidated restart for anything earlier in finalization that
# asked for it (see finalization/gtile-restart-flag.sh and
# install/keybinding/keybinding.sh) - each sets
# OHMYDEBN_CINNAMON_RESTART_NEEDED rather than restarting immediately, so
# two independent restarts in the same run don't race each other. Done
# here, before the "update complete"/"installation complete" messaging
# below, so that's the last thing printed, not this.
# pgrep -x cinnamon here (not at flag-set time) is the up-to-date check of
# whether there's actually a live Cinnamon session to restart.
if [ "${OHMYDEBN_CINNAMON_RESTART_NEEDED:-}" = "1" ] && pgrep -x cinnamon >/dev/null; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Restarting Cinnamon to apply changes"
  setsid /usr/bin/cinnamon --replace >/dev/null 2>&1 &
fi

if [ -f ~/.local/state/ohmydebn ]; then
  VERSION=$(/usr/share/ohmydebn/bin/ohmydebn-version)
  /usr/share/ohmydebn/bin/ohmydebn-headline "OhMyDebn update complete - version: $VERSION"
else
  echo
  /usr/share/ohmydebn/bin/ohmydebn-headline "Installation complete!"
  echo
  toilet -f mono12 "Welcome" | /usr/bin/ttfx rain
  toilet -f mono12 "   to" | /usr/bin/ttfx rain
  toilet -f mono12 "OhMyDebn" | /usr/bin/ttfx rain
  # Create a state file signifying that installation is complete
  mkdir -p ~/.local/state
  touch ~/.local/state/ohmydebn
fi

# OhMyDebn is built around the Cinnamon desktop. If the session that ran
# this install isn't Cinnamon, the user won't see any of it until they
# switch sessions at the login screen.
if [ "$XDG_CURRENT_DESKTOP" != "X-Cinnamon" ]; then
  echo
  /usr/share/ohmydebn/bin/ohmydebn-headline "Log out and select Cinnamon"
  if [ -n "$XDG_CURRENT_DESKTOP" ]; then
    echo "You're currently running $XDG_CURRENT_DESKTOP."
  fi
  echo "Log out, then choose the Cinnamon session from your login screen before logging back in."
fi
