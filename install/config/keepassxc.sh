#!/bin/bash

if [ ! -d ~/.config/keepassxc ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring keepassxc"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/keepassxc ~/.config/
  echo
fi
