#!/bin/bash

# Create directory for Cinnamon themes
mkdir -p ~/.themes

# Create directory for user themes for OhMyDebn/Omarchy
mkdir -p ~/.config/ohmydebn/themes

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

# Symlink ~/.local/share/omarchy/themes to /usr/share/ohmydebn-themes for Aether theme builder
OMARCHY_THEME_SYMLINK_STATE=~/.local/state/ohmydebn-config/omarchy-theme-symlink-20260325
if [ ! -f $OMARCHY_THEME_SYMLINK_STATE ]; then
  rm -rf ~/.local/share/omarchy
  mkdir -p ~/.local/share/omarchy
  ln -s /usr/share/ohmydebn-themes ~/.local/share/omarchy/themes
  touch $OMARCHY_THEME_SYMLINK_STATE
fi
