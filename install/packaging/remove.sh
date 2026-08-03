#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then
  if [ "$NO_UNINSTALL" = false ]; then

    /usr/share/ohmydebn/bin/ohmydebn-headline "tte rain" "Removing any unnecessary packages"

    sudo /usr/bin/apt -y purge brasero \
      deja-dup \
      duplicity \
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

    # Only remove firefox on non-kali systems
    if ! grep -q "kali" /etc/os-release; then
      sudo /usr/bin/apt -y purge firefox*
    fi

    sudo /usr/bin/apt -y autoremove
  fi
fi
