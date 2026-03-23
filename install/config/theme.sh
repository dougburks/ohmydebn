#!/bin/bash

# Create symlinks for all themes
THEME_SYMLINK_STATE=~/.local/state/ohmydebn-config/ohmydebn-theme-symlink-20251121
if [ ! -f $THEME_SYMLINK_STATE ]; then
  mkdir -p ~/.config/ohmydebn/themes
  for f in /usr/share/ohmydebn-themes/*; do
    THEME=$(basename $f)
    rm -f ~/.config/ohmydebn/themes/$THEME
    ln -nfs "$f" ~/.config/ohmydebn/themes/
  done
  touch $THEME_SYMLINK_STATE
fi

# Create directory for user themes
mkdir -p ~/.themes

# Make sure default theme is set
if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Setting default theme"
  mkdir -p ~/.config/ohmydebn/current
  /usr/share/ohmydebn/bin/ohmydebn-theme-set --background 3 Ohmydebn
fi

# Symlink ~/.config/omarchy to ~/.config/ohmydebn for Aether theme builder
if [ ! -e ~/.config/omarchy ]; then
  mkdir -p ~/.config
  ln -s ~/.config/ohmydebn ~/.config/omarchy
fi
