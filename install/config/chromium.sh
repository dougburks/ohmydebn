#!/bin/bash

if [ ! -d ~/.config/chromium ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Configuring chromium"
  mkdir -p ~/.config
  cp -av /opt/ohmydebn/config/chromium ~/.config/
  echo
fi
