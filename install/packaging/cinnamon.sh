#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then

  # Most users are running a normal Debian 13 Cinnamon desktop and are running this script via gnome-terminal
  # In that case, let's change some terminal settings to make the output of this script look nicer
  if dpkg -s "gnome-terminal" >/dev/null 2>&1; then
    PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
    if [ -n "$PROFILE" ]; then
      gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/ foreground-color "'#D3D7CF'"
      gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/ background-color "'#2E3436'"
      gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/ use-theme-colors false
      gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/ palette "['#2e3436', '#cc0000', '#4e9a06', '#c4a000', '#3465a4', '#75507b', '#06989a', '#d3d7cf', '#555753', '#ef2929', '#8ae234', '#fce94f', '#729fcf', '#ad7fa8', '#34e2e2', '#eeeeec']"
    fi
  fi

  toilet -f mono12 "OhMyDebn" | /usr/bin/ttfx rain
  echo

  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring base OS"

fi
