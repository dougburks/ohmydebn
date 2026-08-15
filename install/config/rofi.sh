#!/bin/bash

if ! dpkg -s "rofi" >/dev/null 2>&1; then
  exit 0
fi

mkdir -p ~/.config
ROFI_CONFIG=~/.config/rofi

ROFI_STATE=~/.local/state/ohmydebn-config/rofi-20251014
if [ ! -f $ROFI_STATE ]; then

  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring rofi"

  # If we have the old config, then rename it so we can add the new config
  if [ -d $ROFI_CONFIG ]; then
    mv $ROFI_CONFIG $ROFI_CONFIG-backup-$(date +%Y%m%d-%H%M%S)
  fi

  cp -av /usr/share/ohmydebn/config/rofi ~/.config/
  echo
  touch $ROFI_STATE
fi
