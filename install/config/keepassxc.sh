#!/bin/bash

if ! dpkg -s "keepassxc" >/dev/null 2>&1; then
  exit 0
fi

if [ ! -d ~/.config/keepassxc ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring keepassxc"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/keepassxc ~/.config/
  echo
fi
