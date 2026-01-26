#!/bin/bash

ANTIGRAVITY_DIR=~/.config/Antigravity

# If config doesn't exist, then create it
if [ ! -d $ANTIGRAVITY_DIR ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Copying Antigravity config"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/Antigravity ~/.config/
fi
