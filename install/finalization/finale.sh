#!/bin/bash

if [ -f ~/.local/state/ohmydebn ]; then
  VERSION=$(/usr/share/ohmydebn/bin/ohmydebn-version)
  /usr/share/ohmydebn/bin/ohmydebn-headline "/usr/bin/ttfx rain" "OhMyDebn update complete - version: $VERSION"
else
  echo
  /usr/share/ohmydebn/bin/ohmydebn-headline "/usr/bin/ttfx rain" "Installation complete!"
  echo
  toilet -f mono12 "Welcome" | /usr/bin/ttfx rain
  toilet -f mono12 "   to" | /usr/bin/ttfx rain
  toilet -f mono12 "OhMyDebn" | /usr/bin/ttfx rain
  # Create a state file signifying that installation is complete
  mkdir -p ~/.local/state
  touch ~/.local/state/ohmydebn
fi
