#!/bin/bash

if ! dpkg -s "alacritty" >/dev/null 2>&1; then
  exit 0
fi

ALACRITTY_DIR=~/.config/alacritty
ALACRITTY_CONFIG=$ALACRITTY_DIR/alacritty.toml
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Update old config
if grep -q "alacritty/catppuccin-mocha.toml" $ALACRITTY_CONFIG >/dev/null 2>&1; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Removing old alacritty config"
  mv $ALACRITTY_DIR $ALACRITTY_DIR-backup-$TIMESTAMP
fi

# Some installations got a broken config, so let's fix it
if [ -f ~/.config/alacritty.toml ]; then
  mv $ALACRITTY_DIR $ALACRITTY_DIR-backup-$TIMESTAMP
  mv ~/.config/alacritty.toml $ALACRITTY_DIR-backup-$TIMESTAMP/alacritty.toml-backup-$TIMESTAMP
fi

# If config doesn't exist, then create it
if [ ! -d $ALACRITTY_DIR ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring alacritty terminal emulator"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/alacritty ~/.config/
fi

# If this is the initial installation, then set alacritty as default terminal emulator
if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring alacritty as default terminal emulator"
  gsettings set org.cinnamon.desktop.default-applications.terminal exec "'alacritty'"
fi
