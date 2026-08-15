#!/bin/bash

if ! dpkg -s "cava" >/dev/null 2>&1; then
  exit 0
fi

if [ ! -d ~/.config/cava ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring cava"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/cava ~/.config/
  echo
fi
