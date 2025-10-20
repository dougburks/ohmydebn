#!/bin/bash

NVIM_STATE=~/.local/state/ohmydebn-config/nvim-20251020
if [ ! -f $NVIM_STATE ]; then
  ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring neovim"

  PACKAGE_DIR="${HOME}/.local/share/ohmydebn-nvim"
  CONFIG_DIR="${HOME}/.config/nvim"
  DATA_DIR="${HOME}/.local/share/nvim"
  STATE_DIR="${HOME}/.local/state/nvim"
  CACHE_DIR="${HOME}/.cache/nvim"

  # Check if nvim config already exists
  if [[ -d "$CONFIG_DIR" ]]; then
    CONFIG_DIR_BACKUP="$CONFIG_DIR.backup.20251020"
    echo "Backing up old neovim config to $CONFIG_DIR_BACKUP"
    mv $CONFIG_DIR $CONFIG_DIR_BACKUP
  fi

  # Check if nvim data directory already exists
  if [[ -d "$DATA_DIR" ]]; then
    DATA_DIR_BACKUP="$DATA_DIR.backup.20251020"
    echo "Backing up old neovim data to $DATA_DIR_BACKUP"
    mv $DATA_DIR $DATA_DIR_BACKUP
  fi

  # Check if nvim cache directory already exists
  if [[ -d "$CACHE_DIR" ]]; then
    CACHE_DIR_BACKUP="$CACHE_DIR.backup.20251020"
    echo "Backing up old neovim cache to $CACHE_DIR_BACKUP"
    mv $CACHE_DIR $CACHE_DIR_BACKUP
  fi

  # Create directories if needed
  mkdir -p "$(dirname "$CONFIG_DIR")"
  mkdir -p "$(dirname "$DATA_DIR")"
  mkdir -p "$(dirname "$CACHE_DIR")"

  mkdir -p ${HOME}/.local/share
  cd ${HOME}/.local/share
  echo "Downloading neovim config..."
  wget https://github.com/dougburks/ohmydebn-nvim/releases/download/20251020/ohmydebn-nvim-20251020.tar.gz
  echo -n "Extracting neovim config..."
  tar zxf ohmydebn-nvim-20251020.tar.gz
  echo "done"
  cd - >/dev/null 2>&1

  # Copy files
  cp -r "$PACKAGE_DIR/config" "$CONFIG_DIR"
  cp -r "$PACKAGE_DIR/data" "$DATA_DIR"
  cp -r "$PACKAGE_DIR/cache" "$CACHE_DIR"

  # Ensure proper ownership of all nvim directories
  chown -R "${USER}:${USER}" "$CONFIG_DIR"
  chown -R "${USER}:${USER}" "$DATA_DIR"
  chown -R "${USER}:${USER}" "$CACHE_DIR"

  # Create link for current theme
  ln -snf "${HOME}/.config/ohmydebn/current/theme/neovim.lua" "${CONFIG_DIR}/lua/plugins/theme.lua"

  for dir in $DATA_DIR/lazy/*/; do
    if [ -d "$dir/.git" ]; then
      git --git-dir="$dir/.git" --work-tree="$dir" restore .
    fi
  done

  # 20250915 A new version of LazyVim has been released that requires Neovim >= 0.11.0.
  # Debian stable repo does not include this new version yet.
  # In the meantime, pin LazyVim to v14 as described at:
  # https://github.com/LazyVim/LazyVim/issues/6421
  CORE=$CONFIG_DIR/lua/plugins/core.lua
  if [ ! -f $CORE ]; then
    ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Creating $CORE"
    mkdir -p $CONFIG_DIR/lua/plugins
    cp -av ~/.local/share/ohmydebn/config/nvim/lua/plugins/core.lua $CORE
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    LAZYVIM=~/.local/share/nvim/lazy/LazyVim
    if [ -d $LAZYVIM ]; then
      mv $LAZYVIM $LAZYVIM-backup-$TIMESTAMP
    fi
    LAZYLOCK=$CONFIG_DIR/lazy-lock.json
    if [ -f $LAZYLOCK ]; then
      mv $LAZYLOCK $LAZYLOCK-backup-$TIMESTAMP
    fi
  fi

  touch $NVIM_STATE
  echo "Neovim setup complete!"
fi
