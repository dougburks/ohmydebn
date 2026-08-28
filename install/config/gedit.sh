#!/bin/bash

if ! dpkg -s "gedit" >/dev/null 2>&1; then
  exit 0
fi

STATE_DIR=~/.local/state/ohmydebn-config
GEDIT_STATE=$STATE_DIR/gedit

if [ ! -f $GEDIT_STATE ]; then

  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring gedit"
  # gsettings keys can be renamed/removed between gedit versions (e.g.
  # "theme-variant" doesn't exist before gedit 47, so it's absent on Mint's
  # 46.2) - `|| true` keeps each line's exit status 0 so a missing key is
  # silently skipped instead of aborting the rest of the install under the
  # caller's `set -e`. Not worth a warning: this is a known, permanent
  # version gate, not something actionable.
  gsettings set org.gnome.gedit.preferences.editor highlight-current-line false || true
  gsettings set org.gnome.gedit.preferences.editor display-line-numbers false || true
  gsettings set org.gnome.gedit.preferences.ui theme-variant 'light' || true
  mkdir -p $STATE_DIR
  touch $GEDIT_STATE

fi
