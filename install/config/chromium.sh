#!/bin/bash

if ! dpkg -s "chromium" >/dev/null 2>&1; then
  exit 0
fi

if [ ! -d ~/.config/chromium ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring chromium"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/chromium ~/.config/
  echo
fi
