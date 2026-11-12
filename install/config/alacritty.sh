#!/bin/bash

if ! dpkg -s "alacritty" >/dev/null 2>&1; then
  return 0
fi

ALACRITTY_DIR=~/.config/alacritty
ALACRITTY_CONFIG=$ALACRITTY_DIR/alacritty.toml
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ALACRITTY_VERSION=$(dpkg-query -W -f='${Version}' alacritty)

# Update old config
if grep -q "alacritty/catppuccin-mocha.toml" $ALACRITTY_CONFIG >/dev/null 2>&1; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Removing old alacritty config"
  mv $ALACRITTY_DIR $ALACRITTY_DIR-backup-$TIMESTAMP
fi

# Some installations got a broken config, so let's fix it. The alacritty
# directory may not exist (or the block above may have just moved it), and
# a failed mv here would stop the whole install.
if [ -f ~/.config/alacritty.toml ]; then
  if [ -d $ALACRITTY_DIR ]; then
    mv $ALACRITTY_DIR $ALACRITTY_DIR-backup-$TIMESTAMP
  fi
  mkdir -p $ALACRITTY_DIR-backup-$TIMESTAMP
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
  if dpkg --compare-versions "$ALACRITTY_VERSION" lt "0.14.0"; then
    sed -i \
      -e '/^\[general\]$/d' \
      -e 's/^\[terminal\]$/[shell]/' \
      -e 's/^shell = /program = /' \
      $ALACRITTY_CONFIG
  fi
fi

# The other way round: a config written in the pre-0.14 form above, once
# alacritty itself is upgraded past 0.14 (Linux Mint 22's 0.13.2 to Mint
# 27's 0.16), makes every window warn that "import" and "shell" are
# deprecated. Put both keys back in the 0.14+ form, keeping a backup.
# The old form is told apart by what's missing, not by "import =" alone:
# that line still starts the converted file's [general] table, and a
# second [general] on the next update would be invalid TOML, which
# alacritty refuses to start with. ohmydebn-doctor tests the same way.
if [ -f "$ALACRITTY_CONFIG" ] && dpkg --compare-versions "$ALACRITTY_VERSION" ge "0.14.0"; then
  OLD_IMPORT=false
  OLD_SHELL=false
  if grep -qE '^import[[:space:]]*=' "$ALACRITTY_CONFIG" && ! grep -qE '^\[general\][[:space:]]*$' "$ALACRITTY_CONFIG"; then
    OLD_IMPORT=true
  fi
  if grep -qE '^\[shell\][[:space:]]*$' "$ALACRITTY_CONFIG"; then
    OLD_SHELL=true
  fi
  if [ "$OLD_IMPORT" = true ] || [ "$OLD_SHELL" = true ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Updating alacritty config for Alacritty $ALACRITTY_VERSION"
    cp -a "$ALACRITTY_CONFIG" "$ALACRITTY_CONFIG.backup-$TIMESTAMP"
    # [general] goes right above the top-level import, which also takes in
    # any top-level keys after it (live_config_reload, working_directory),
    # where 0.14+ expects them too. --follow-symlinks keeps a linked config
    # linked, as in ohmydebn-theme-set-terminal.
    if [ "$OLD_IMPORT" = true ]; then
      sed -i --follow-symlinks 's/^import[[:space:]]*=/[general]\nimport =/' "$ALACRITTY_CONFIG"
    fi
    # program becomes shell while its table is still named [shell], so
    # the range finds it; then the table is renamed.
    if [ "$OLD_SHELL" = true ]; then
      sed -i --follow-symlinks \
        -e '/^\[shell\][[:space:]]*$/,/^\[/ s/^program[[:space:]]*=/shell =/' \
        -e 's/^\[shell\][[:space:]]*$/[terminal]/' \
        "$ALACRITTY_CONFIG"
    fi
  fi
fi

# If this is the initial installation, then set alacritty as default
# terminal emulator - through ohmydebn-alacritty, which starts it as an X11
# window in a Wayland session so Cinnamon gives it a themed title bar (see
# that script). Cinnamon's Ctrl+Alt+T and Nemo's Open in Terminal use this.
ALACRITTY_WRAPPER=/usr/share/ohmydebn/bin/ohmydebn-alacritty
if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring alacritty as default terminal emulator"
  gsettings set org.cinnamon.desktop.default-applications.terminal exec "'$ALACRITTY_WRAPPER'"
fi

# Existing installs got plain alacritty as the default terminal: switch it
# to the wrapper once, only while it's still that default, so a terminal
# the user chose themselves stays theirs.
ALACRITTY_WRAPPER_STATE=~/.local/state/ohmydebn-config/alacritty-default-terminal-wrapper-20261112
if [ ! -f "$ALACRITTY_WRAPPER_STATE" ]; then
  if [ "$(gsettings get org.cinnamon.desktop.default-applications.terminal exec 2>/dev/null || true)" = "'alacritty'" ]; then
    gsettings set org.cinnamon.desktop.default-applications.terminal exec "'$ALACRITTY_WRAPPER'"
  fi
  mkdir -p ~/.local/state/ohmydebn-config
  touch "$ALACRITTY_WRAPPER_STATE"
fi
