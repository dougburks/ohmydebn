#!/bin/bash

if [ ! -d ~/.config/chromium ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring chromium"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/chromium ~/.config/
  echo
fi
