#!/bin/bash

# Create symlinks for all themes
THEME_SYMLINK_STATE=~/.local/state/ohmydebn-config/ohmydebn-theme-symlink-20251115
if [ ! -f $THEME_SYMLINK_STATE ]; then
  mkdir -p ~/.config/ohmydebn/themes
  for f in /opt/ohmydebn-themes/* /opt/ohmydebn-themes-omarchy/*; do
    THEME=$(basename $f)
    rm -f ~/.config/ohmydebn/themes/$THEME
    ln -nfs "$f" ~/.config/ohmydebn/themes/
  done
  touch $THEME_SYMLINK_STATE
fi

# Download theme support
THEME_STATE=~/.local/state/ohmydebn-config/ohmydebn-themes-20250911
if [ ! -f $THEME_STATE ]; then
  cd
  echo "Downloading themes..."
  wget https://github.com/dougburks/ohmydebn-themes/releases/download/20250911/ohmydebn-themes.tar.gz
  echo -n "Installing themes..."
  tar zxf ohmydebn-themes.tar.gz
  echo "done"
  rm -f ohmydebn-themes.tar.gz
  touch $THEME_STATE
fi

# Make sure default theme is set
if [ ! -f ~/.local/state/ohmydebn ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Setting default theme"
  mkdir -p ~/.config/ohmydebn/current
  /opt/ohmydebn/bin/ohmydebn-theme-set Ohmydebn
fi

# Symlink ~/.config/omarchy to ~/.config/ohmydebn for Aether theme builder
if [ ! -e ~/.config/omarchy ]; then
  mkdir -p ~/.config
  ln -s ~/.config/ohmydebn ~/.config/omarchy
fi

# Symlink omarchy-theme-set to ohmydebn-theme-set for Aether
if [ ! -e ~/.local/bin/omarchy-theme-set ]; then
  mkdir -p ~/.local/bin
  rm -f ~/.local/bin/omarchy-theme-set
  ln -s /opt/ohmydebn/bin/ohmydebn-theme-set ~/.local/bin/omarchy-theme-set
fi
