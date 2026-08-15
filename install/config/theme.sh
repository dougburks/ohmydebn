#!/bin/bash

# Create directory for Cinnamon themes
mkdir -p ~/.themes

# Create directory for user themes for OhMyDebn/Omarchy
mkdir -p ~/.config/ohmydebn/themes

# Make sure default theme is set
if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Setting default theme"
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

# Create URL handler for Aether theme builder handler
OMARCHY_THEME_URL_HANDLER_STATE=~/.local/state/ohmydebn-config/omarchy-theme-url-handler-20260814
if [ ! -f $OMARCHY_THEME_URL_HANDLER_STATE ]; then

  # Allow Aether's activation wait to read OhMyDebn's real theme.name/background
  mkdir -p ~/.local/state/omarchy
  ln -s ~/.config/ohmydebn/current ~/.local/state/omarchy/current

  # Aether requires shell.qml to handle URLs
  mkdir -p ~/.local/share/omarchy/shell
  cat <<EOF >~/.local/share/omarchy/shell/shell.qml
// Omarchy compatibility marker for Aether.
// OhMyDebn provides the omarchy-theme-set CLI and maps ~/.config/omarchy to
// ~/.config/ohmydebn, but ships no Quickshell UI. Aether's --handle-url
// installer requires <omarchy>/shell/shell.qml to exist before it will
// render themes into the Omarchy themes dir and run omarchy-theme-set.
// This placeholder satisfies that existence check; OhMyDebn has no shell
// component to load this file.
import QtQuick
Item { }
EOF

  touch $OMARCHY_THEME_URL_HANDLER_STATE
fi
