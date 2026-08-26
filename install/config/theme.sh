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

# Backfill a themed fastfetch config for installs that already had a theme
# active before ohmydebn-theme-set-fastfetch existed - the "default theme is
# set" block above only runs ohmydebn-theme-set on a truly fresh install, so
# an upgrader's current/theme/ was populated by an older
# ohmydebn-theme-set-templates that never generated config.jsonc. Templating
# directly into the already-active theme dir (rather than re-running the
# full ohmydebn-theme-set) avoids side effects like cycling the background.
# (Marker bumped once from -20260816: the active theme may have no
# colors.toml at all - older static themes ship every app's config directly
# instead of using the {{ }} templating pipeline - in which case
# ohmydebn-theme-set-templates has nothing to generate. That's expected;
# ohmydebn-theme-set-fastfetch itself now falls back to a static default
# config in that case, rather than leaving fastfetch unconfigured.)
FASTFETCH_CONFIG_BACKFILL_STATE=~/.local/state/ohmydebn-config/fastfetch-config-backfill-20260817
if [ ! -f $FASTFETCH_CONFIG_BACKFILL_STATE ]; then
  if [ -d ~/.config/ohmydebn/current/theme ]; then
    /usr/share/ohmydebn/bin/ohmydebn-theme-set-templates ~/.config/ohmydebn/current/theme
    /usr/share/ohmydebn/bin/ohmydebn-theme-set-fastfetch
  fi
  touch $FASTFETCH_CONFIG_BACKFILL_STATE
fi

# Backfill the GTK pickers' color file for installs that already had a theme
# active before ohmydebn-theme-set-picker existed - same reasoning as the
# fastfetch backfill above: the "default theme is set" block only runs
# ohmydebn-theme-set on a truly fresh install, so an upgrader's
# current/picker-colors was simply never written. ohmydebn-menu-picker falls
# back to a generic default palette when that file is missing, so upgraders
# saw the wrong colors until they next ran ohmydebn-theme-set themselves.
# Resolve colors from the already-active current/theme (not the original
# theme source) and only touch the picker's own color file - not the full
# ohmydebn-theme-set - to avoid side effects like cycling the background.
PICKER_COLORS_BACKFILL_STATE=~/.local/state/ohmydebn-config/picker-colors-backfill-20260825
if [ ! -f $PICKER_COLORS_BACKFILL_STATE ]; then
  if [ -d ~/.config/ohmydebn/current/theme ]; then
    COLORS_SOURCE=$(/usr/share/ohmydebn/bin/ohmydebn-theme-set-colors ~/.config/ohmydebn/current/theme)
    /usr/share/ohmydebn/bin/ohmydebn-theme-set-picker "$COLORS_SOURCE"
    /usr/share/ohmydebn/bin/ohmydebn-theme-set-colors-delete "$COLORS_SOURCE"
  fi
  touch $PICKER_COLORS_BACKFILL_STATE
fi
