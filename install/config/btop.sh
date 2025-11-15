#!/bin/bash

OHMYDEBN_STATE=~/.local/state/ohmydebn-config
mkdir -p $OHMYDEBN_STATE

BTOP_CONFIG_STATE=$OHMYDEBN_STATE/btop-config-20250916
if [ ! -f $BTOP_CONFIG_STATE ]; then
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BTOP_CONFIG=~/.config/btop
  if [ -d $BTOP_CONFIG ]; then
    mv $BTOP_CONFIG $BTOP_CONFIG-backup-$TIMESTAMP
  fi
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Configuring btop"
  cp -av /opt/ohmydebn/config/btop ~/.config/
  touch $BTOP_CONFIG_STATE
fi

BTOP_THEMES_DIR=~/.config/btop/themes
mkdir -p $BTOP_THEMES_DIR

BTOP_CURRENT_THEME=$BTOP_THEMES_DIR/current.theme
if [ ! -L $BTOP_CURRENT_THEME ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Configuring btop theme"
  ln -snf ~/.config/ohmydebn/current/theme/btop.theme $BTOP_CURRENT_THEME
fi
