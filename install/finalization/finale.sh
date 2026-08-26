#!/bin/bash

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
