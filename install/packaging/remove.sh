#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then
  if [ "$NO_UNINSTALL" = false ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "tte rain" "Removing any unnecessary packages"
    sudo /usr/bin/apt -y purge brasero \
      deja-dup \
      duplicity \
      firefox* \
      gnome-calculator \
      gnome-chess \
      gnome-games \
      goldendict-ng \
      hexchat \
      hoichess \
      libreoffice-* \
      pidgin \
      remmina \
      thunderbird \
      transmission* \
      x11vnc
    sudo /usr/bin/apt -y autoremove
  fi
fi
