#!/bin/bash

BAT_BIN=/usr/local/bin/bat
if [ ! -e $BAT_BIN ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Creating symbolic link for bat"
  sudo ln -s /usr/bin/batcat /usr/local/bin/bat
fi

BAT_STATE=~/.local/state/ohmydebn-config/bat-20251110
if [ ! -f $BAT_STATE ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Configuring bat"
  BAT_CONFIG=~/.config/bat
  if [ -d $BAT_CONFIG ]; then
    mv $BAT_CONFIG $BAT_CONFIG-backup-$(date +%Y%m%d-%H%M%S)
  fi
  mkdir -p ~/.config
  cp -av /opt/ohmydebn/config/bat ~/.config/
  mkdir -p ~/.local/state/ohmydebn-config
  touch $BAT_STATE
fi

BAT_CACHE_METADATA=~/.cache/bat/metadata.yaml
if [ ! -f $BAT_CACHE_METADATA ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Building cache for bat"
  bat cache --build
fi
