#!/bin/bash

if [ ! -d ~/.config/cava ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring cava"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/cava ~/.config/
  echo
fi
