#!/bin/bash

NVIM_CONFIG_DIR=~/.config/nvim
if [ ! -d $NVIM_CONFIG_DIR ]; then
  ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring neovim with lazyvim"
  mkdir -p ~/.config
  git clone https://github.com/LazyVim/starter $NVIM_CONFIG_DIR
  rm -rf $NVIM_CONFIG_DIR/.git
fi

NVIM_PLUGINS=$NVIM_CONFIG_DIR/lua/plugins
mkdir -p $NVIM_PLUGINS
if grep -q "colorscheme = \"catppuccin\"" $NVIM_PLUGINS/core.lua >/dev/null 2>&1; then
  ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Disabling old static neovim theme config"
  mv $NVIM_PLUGINS/core.lua $NVIM_PLUGINS/core.lua.disabled
fi

NVIM_THEME=$NVIM_PLUGINS/theme.lua
if [ ! -L $NVIM_THEME ]; then
  ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring neovim theme"
  ln -snf ~/.config/ohmydebn/current/theme/neovim.lua $NVIM_THEME
fi

LAZYVIM=$NVIM_CONFIG_DIR/lazyvim.json
if [ ! -f $LAZYVIM ]; then
  ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Creating $LAZYVIM"
  cp -av ~/.local/share/ohmydebn/config/nvim/lazyvim.json $LAZYVIM
fi

SCROLLING=$NVIM_CONFIG_DIR/lua/plugins/snacks-animated-scrolling-off.lua
if [ ! -f $SCROLLING ]; then
  ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Creating $SCROLLING"
  mkdir -p $NVIM_CONFIG_DIR/lua/plugins
  cp -av ~/.local/share/ohmydebn/config/nvim/lua/plugins/snacks-animated-scrolling-off.lua $SCROLLING
fi

TRANSPARENCY=$NVIM_CONFIG_DIR/plugin/after/transparency.lua
if [ ! -f $TRANSPARENCY ]; then
  ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Creating $TRANSPARENCY"
  mkdir -p $NVIM_CONFIG_DIR/plugin/after
  cp -av ~/.local/share/ohmydebn/config/nvim/plugin/after/transparency.lua $TRANSPARENCY
fi

NVIM_OPTIONS=$NVIM_CONFIG_DIR/lua/config/options.lua
if ! grep -q "vim.opt.relativenumber = false" $NVIM_OPTIONS >/dev/null 2>&1; then
  echo "vim.opt.relativenumber = false" >>$NVIM_OPTIONS
fi

# 20250915 A new version of LazyVim has been released that requires Neovim >= 0.11.0.
# Debian stable repo does not include this new version yet.
# In the meantime, pin LazyVim to v14 as described at:
# https://github.com/LazyVim/LazyVim/issues/6421
CORE=$NVIM_CONFIG_DIR/lua/plugins/core.lua
if [ ! -f $CORE ]; then
  ~/.local/share/ohmydebn/bin/ohmydebn-headline "cat" "Creating $CORE"
  mkdir -p $NVIM_CONFIG_DIR/lua/plugins
  cp -av ~/.local/share/ohmydebn/config/nvim/lua/plugins/core.lua $CORE
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  LAZYVIM=~/.local/share/nvim/lazy/LazyVim
  if [ -d $LAZYVIM ]; then
    mv $LAZYVIM $LAZYVIM-backup-$TIMESTAMP
  fi
  LAZYLOCK=$NVIM_CONFIG_DIR/lazy-lock.json
  if [ -f $LAZYLOCK ]; then
    mv $LAZYLOCK $LAZYLOCK-backup-$TIMESTAMP
  fi
fi
