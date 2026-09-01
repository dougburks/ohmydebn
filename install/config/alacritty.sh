#!/bin/bash

if ! dpkg -s "alacritty" >/dev/null 2>&1; then
  exit 0
fi

ALACRITTY_DIR=~/.config/alacritty
ALACRITTY_CONFIG=$ALACRITTY_DIR/alacritty.toml
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Update old config
if grep -q "alacritty/catppuccin-mocha.toml" $ALACRITTY_CONFIG >/dev/null 2>&1; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Removing old alacritty config"
  mv $ALACRITTY_DIR $ALACRITTY_DIR-backup-$TIMESTAMP
fi

# Some installations got a broken config, so let's fix it
if [ -f ~/.config/alacritty.toml ]; then
  mv $ALACRITTY_DIR $ALACRITTY_DIR-backup-$TIMESTAMP
  mv ~/.config/alacritty.toml $ALACRITTY_DIR-backup-$TIMESTAMP/alacritty.toml-backup-$TIMESTAMP
fi

# If config doesn't exist, then create it
if [ ! -d $ALACRITTY_DIR ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring alacritty terminal emulator"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/alacritty ~/.config/

  # The packaged config uses Alacritty 0.14+ syntax (general.import,
  # terminal.shell). Pre-0.14 (e.g. Mint's 0.13.2) doesn't understand either
  # key at all, so on older installs rewrite them to the equivalent
  # pre-0.14 form here instead of shipping a second config to keep in sync -
  # only these two keys differ between the syntaxes, everything else
  # (font/window/env) stays identical either way.
  ALACRITTY_VERSION=$(dpkg-query -W -f='${Version}' alacritty)
  if dpkg --compare-versions "$ALACRITTY_VERSION" lt "0.14.0"; then
    sed -i \
      -e '/^\[general\]$/d' \
      -e 's/^\[terminal\]$/[shell]/' \
      -e 's/^shell = /program = /' \
      $ALACRITTY_CONFIG
  fi
fi

# If this is the initial installation, then set alacritty as default terminal emulator
if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring alacritty as default terminal emulator"
  gsettings set org.cinnamon.desktop.default-applications.terminal exec "'alacritty'"
fi
