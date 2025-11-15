#!/bin/bash

if [ -f ~/.local/state/ohmydebn ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "tte rain" "OhMyDebn update complete!"
else
  echo
  /opt/ohmydebn/bin/ohmydebn-headline "tte rain" "Installation complete!"
  echo
  toilet -f mono12 "Welcome" | tte rain
  toilet -f mono12 "   to" | tte rain
  toilet -f mono12 "OhMyDebn" | tte rain
  # Create a state file signifying that installation is complete
  mkdir -p ~/.local/state
  touch ~/.local/state/ohmydebn
fi
