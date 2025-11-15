#!/bin/bash

if [ ! -d ~/.config/keepassxc ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Configuring keepassxc"
  mkdir -p ~/.config
  cp -av /opt/ohmydebn/config/keepassxc ~/.config/
  echo
fi
