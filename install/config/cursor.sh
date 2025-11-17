#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Setting cursor theme"
  gsettings set org.cinnamon.desktop.interface cursor-theme "'Bibata-Modern-Classic'"
fi
