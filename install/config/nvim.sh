#!/bin/bash

# Sourced by install/config/all.sh, so no `exit`: that would end the whole
# install. ohmydebn-neovim-plugins is OhMyDebn's tested LazyVim setup: its
# config, and every plugin, parser and Mason tool it needs, built against
# ohmydebn-neovim - so Neovim downloads nothing on its own, and plugins
# change only when OhMyDebn ships a new tested set.
NVIM_SEED=/usr/lib/ohmydebn-neovim-plugins
if dpkg -s "ohmydebn-neovim-plugins" >/dev/null 2>&1; then

  NVIM_CONFIG_DIR=~/.config/nvim
  NVIM_DATA_DIR=~/.local/share/nvim
  NVIM_STATE_DIR=~/.local/state/ohmydebn-config
  mkdir -p $NVIM_STATE_DIR

  if [ ! -d $NVIM_CONFIG_DIR ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring neovim with lazyvim"
    mkdir -p ~/.config
    cp -a $NVIM_SEED/config $NVIM_CONFIG_DIR
  fi

  NVIM_PLUGINS=$NVIM_CONFIG_DIR/lua/plugins
  mkdir -p $NVIM_PLUGINS
  if grep -q "colorscheme = \"catppuccin\"" $NVIM_PLUGINS/core.lua >/dev/null 2>&1; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Disabling old static neovim theme config"
    mv $NVIM_PLUGINS/core.lua $NVIM_PLUGINS/core.lua.disabled
  fi

  NVIM_THEME=$NVIM_PLUGINS/theme.lua
  if [ ! -L $NVIM_THEME ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring neovim theme"
    ln -snf ~/.config/ohmydebn/current/theme/neovim.lua $NVIM_THEME
  fi

  LAZYVIM=$NVIM_CONFIG_DIR/lazyvim.json
  if [ ! -f $LAZYVIM ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Creating $LAZYVIM"
    cp -av /usr/share/ohmydebn/config/nvim/lazyvim.json $LAZYVIM
  fi

  SCROLLING=$NVIM_PLUGINS/snacks-animated-scrolling-off.lua
  if [ ! -f $SCROLLING ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Creating $SCROLLING"
    cp -av /usr/share/ohmydebn/config/nvim/lua/plugins/snacks-animated-scrolling-off.lua $SCROLLING
  fi

  TRANSPARENCY=$NVIM_CONFIG_DIR/plugin/after/transparency.lua
  TRANSPARENCY_STATE=$NVIM_STATE_DIR/nvim-transparency-20260308
  if [ ! -f $TRANSPARENCY_STATE ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Updating $TRANSPARENCY"
    mkdir -p $NVIM_CONFIG_DIR/plugin/after
    cp -av /usr/share/ohmydebn/config/nvim/plugin/after/transparency.lua $TRANSPARENCY
    touch $TRANSPARENCY_STATE
  fi

  # Plain line numbers instead of LazyVim's relative ones, once: the
  # package's options.lua already has this, so it's only for configs made
  # before it did. Checked on every run, it put the line back each time a
  # user changed it, and its append stopped the install when a config of the
  # user's own had no lua/config directory. Any relativenumber line of the
  # user's means they chose, and is left alone.
  NVIM_OPTIONS=$NVIM_CONFIG_DIR/lua/config/options.lua
  NVIM_RELATIVENUMBER_STATE=$NVIM_STATE_DIR/nvim-relativenumber-20260929
  if [ ! -f $NVIM_RELATIVENUMBER_STATE ]; then
    if ! grep -q "relativenumber" $NVIM_OPTIONS >/dev/null 2>&1; then
      mkdir -p $NVIM_CONFIG_DIR/lua/config
      echo "vim.opt.relativenumber = false" >>$NVIM_OPTIONS
    fi
    touch $NVIM_RELATIVENUMBER_STATE
  fi

  ALL_THEMES=$NVIM_PLUGINS/all-themes.lua
  if [ ! -f $ALL_THEMES ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Creating $ALL_THEMES"
    cp -av /usr/share/ohmydebn/config/nvim/lua/plugins/all-themes.lua $ALL_THEMES
  fi

  HOTRELOAD=$NVIM_PLUGINS/omarchy-theme-hotreload.lua
  if [ ! -f $HOTRELOAD ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Creating $HOTRELOAD"
    cp -av /usr/share/ohmydebn/config/nvim/lua/plugins/omarchy-theme-hotreload.lua $HOTRELOAD
  fi

  # 20260926 Neovim now comes from ohmydebn-neovim (current upstream) instead
  # of the distro's, and plugins from ohmydebn-neovim-plugins. Earlier releases
  # pinned LazyVim to v14 and nvim-treesitter/gitsigns.nvim to old commits for
  # Debian 13's Neovim 0.10; the tested plugin set replaces those pins, so
  # they're set aside (renamed, not deleted), lazy.nvim stops checking for
  # plugin updates on its own, and OhMyDebn's offline settings go in (Mason
  # doesn't refresh its registry at startup, no LazyVim "What's new?" window).
  NVIM_MIGRATION_STATE=$NVIM_STATE_DIR/nvim-plugins-20260926
  if [ ! -f $NVIM_MIGRATION_STATE ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Moving neovim to OhMyDebn's tested plugin set"
    NVIM_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    for NVIM_PIN in core treesitter gitsigns; do
      if [ -f $NVIM_PLUGINS/$NVIM_PIN.lua ]; then
        mv -v $NVIM_PLUGINS/$NVIM_PIN.lua $NVIM_PLUGINS/$NVIM_PIN.lua.disabled-$NVIM_TIMESTAMP
      fi
    done
    NVIM_LAZY=$NVIM_CONFIG_DIR/lua/config/lazy.lua
    if [ -f $NVIM_LAZY ]; then
      sed -i 's/^\(\s*\)enabled = true, -- check for plugin updates periodically$/\1enabled = false, -- OhMyDebn ships tested plugin versions/' $NVIM_LAZY
    fi
    cp -av $NVIM_SEED/config/lua/plugins/ohmydebn-offline.lua $NVIM_PLUGINS/
    touch $NVIM_MIGRATION_STATE
  fi

  # Install the package's plugins, parsers and Mason tools into the user's
  # own directories, where lazy.nvim, nvim-treesitter and Mason manage them as
  # usual - once per tested set (the stamp is its lockfile's checksum), so a
  # user's own :Lazy update stands until the next OhMyDebn plugin release.
  # Only OhMyDebn's plugins and tools are touched: anything the user added
  # stays, and what gets replaced is kept in one backup directory, which the
  # next refresh deletes.
  NVIM_SEED_STAMP=$NVIM_STATE_DIR/nvim-plugins-seeded
  NVIM_SEED_SUM=$(sha256sum $NVIM_SEED/config/lazy-lock.json | cut -d' ' -f1)
  if [ "$(cat $NVIM_SEED_STAMP 2>/dev/null)" != "$NVIM_SEED_SUM" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Installing OhMyDebn's tested neovim plugins"
    # The stamp is written only if every step worked, so anything that fails
    # is retried on the next update rather than left half-done for good.
    NVIM_SEED_OK=true
    NVIM_SEED_PLUGINS=$(jq -r 'to_entries[] | "\(.key) \(.value.commit)"' $NVIM_SEED/config/lazy-lock.json) || NVIM_SEED_PLUGINS=""
    if [ -z "$NVIM_SEED_PLUGINS" ]; then
      echo "Could not read $NVIM_SEED/config/lazy-lock.json, so neovim's plugins were not updated."
      NVIM_SEED_OK=false
    else
      rm -rf $NVIM_DATA_DIR/ohmydebn-backup-*
      NVIM_BACKUP=$NVIM_DATA_DIR/ohmydebn-backup-$(date +%Y%m%d-%H%M%S)
      mkdir -p $NVIM_DATA_DIR/lazy

      # Plugins: each one the package ships, unless the user's copy is
      # already at the tested commit.
      while read -r NVIM_NAME NVIM_COMMIT; do
        if [ -d $NVIM_DATA_DIR/lazy/$NVIM_NAME ]; then
          if [ "$(git -C $NVIM_DATA_DIR/lazy/$NVIM_NAME rev-parse HEAD 2>/dev/null)" = "$NVIM_COMMIT" ]; then
            continue
          fi
          mkdir -p $NVIM_BACKUP/lazy
          mv $NVIM_DATA_DIR/lazy/$NVIM_NAME $NVIM_BACKUP/lazy/ || {
            NVIM_SEED_OK=false
            continue
          }
        fi
        cp -a $NVIM_SEED/data/lazy/$NVIM_NAME $NVIM_DATA_DIR/lazy/$NVIM_NAME || NVIM_SEED_OK=false
      done <<<"$NVIM_SEED_PLUGINS"

      # Lockfile: the package's entries win; the user's own plugins keep
      # theirs.
      NVIM_LOCK=$NVIM_CONFIG_DIR/lazy-lock.json
      if [ -f $NVIM_LOCK ] && jq -e . $NVIM_LOCK >/dev/null 2>&1; then
        jq -S -s '.[0] * .[1]' $NVIM_LOCK $NVIM_SEED/config/lazy-lock.json >$NVIM_LOCK.tmp &&
          mv $NVIM_LOCK.tmp $NVIM_LOCK || NVIM_SEED_OK=false
      else
        cp $NVIM_SEED/config/lazy-lock.json $NVIM_LOCK || NVIM_SEED_OK=false
      fi

      # Parsers and their queries: OhMyDebn's are added or replaced, any the
      # user installed stay.
      mkdir -p $NVIM_DATA_DIR/site
      cp -a $NVIM_SEED/data/site/. $NVIM_DATA_DIR/site/ || NVIM_SEED_OK=false

      # Mason: OhMyDebn's tools (each unless already at the same version) and
      # its registry snapshot; tools the user installed stay.
      mkdir -p $NVIM_DATA_DIR/mason/packages
      for NVIM_PKG in $NVIM_SEED/data/mason/packages/*/; do
        NVIM_PKG=$(basename $NVIM_PKG)
        if [ -d $NVIM_DATA_DIR/mason/packages/$NVIM_PKG ]; then
          if cmp -s $NVIM_SEED/data/mason/packages/$NVIM_PKG/mason-receipt.json $NVIM_DATA_DIR/mason/packages/$NVIM_PKG/mason-receipt.json; then
            continue
          fi
          mkdir -p $NVIM_BACKUP/mason
          mv $NVIM_DATA_DIR/mason/packages/$NVIM_PKG $NVIM_BACKUP/mason/ || {
            NVIM_SEED_OK=false
            continue
          }
        fi
        cp -a $NVIM_SEED/data/mason/packages/$NVIM_PKG $NVIM_DATA_DIR/mason/packages/$NVIM_PKG || NVIM_SEED_OK=false
      done
      for NVIM_DIR in bin share; do
        mkdir -p $NVIM_DATA_DIR/mason/$NVIM_DIR
        cp -a $NVIM_SEED/data/mason/$NVIM_DIR/. $NVIM_DATA_DIR/mason/$NVIM_DIR/ || NVIM_SEED_OK=false
      done
      rm -rf $NVIM_DATA_DIR/mason/registries
      cp -a $NVIM_SEED/data/mason/registries $NVIM_DATA_DIR/mason/registries || NVIM_SEED_OK=false

      if [ -d $NVIM_BACKUP ]; then
        echo "Replaced neovim plugins and tools were moved to $NVIM_BACKUP"
      fi
    fi
    if [ $NVIM_SEED_OK = true ]; then
      echo "$NVIM_SEED_SUM" >$NVIM_SEED_STAMP
    else
      echo "Some of neovim's plugins could not be installed. The next OhMyDebn update will try again."
    fi
  fi
fi
