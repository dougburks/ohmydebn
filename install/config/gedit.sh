#!/bin/bash

if ! dpkg -s "gedit" >/dev/null 2>&1; then
  exit 0
fi

STATE_DIR=~/.local/state/ohmydebn-config
GEDIT_STATE=$STATE_DIR/gedit

if [ ! -f $GEDIT_STATE ]; then

  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring gedit"
  gsettings set org.gnome.gedit.preferences.editor highlight-current-line false
  gsettings set org.gnome.gedit.preferences.editor display-line-numbers false
  gsettings set org.gnome.gedit.preferences.ui theme-variant 'light'
  mkdir -p $STATE_DIR
  touch $GEDIT_STATE

fi
