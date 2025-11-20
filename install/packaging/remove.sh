#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then
  if [ "$NO_UNINSTALL" = false ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "tte rain" "Removing any unnecessary packages"
    sudo apt -y purge brasero \
      firefox* \
      thunderbird \
      gnome-calculator \
      gnome-chess \
      gnome-games \
      goldendict-ng \
      hexchat \
      hoichess \
      pidgin \
      remmina \
      transmission* \
      x11vnc
    sudo apt -y autoremove
  fi
fi
