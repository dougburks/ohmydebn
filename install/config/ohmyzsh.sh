#!/bin/bash

if ! dpkg -s "zsh" >/dev/null 2>&1; then
  return 0
fi

# One-time repair for installs that hit a bug of the old Oh My Zsh download
# (its installer moved OhMyDebn's .zshrc aside when a first install's
# download had failed and a later update's worked): OhMyDebn's .zshrc sits
# at ~/.zshrc.pre-oh-my-zsh, and ~/.zshrc holds only the PATH lines zsh.sh
# appends. Put OhMyDebn's back (keeping the stub as a backup), recognized
# by the Starship line only OhMyDebn's .zshrc has. Before the move below,
# which then applies to the restored file too.
ZSHRC_REPAIR_STATE=~/.local/state/ohmydebn-config/zshrc-restore-20261012
if [ ! -f $ZSHRC_REPAIR_STATE ]; then
  if [ -f ~/.zshrc.pre-oh-my-zsh ] && grep -q 'starship init zsh' ~/.zshrc.pre-oh-my-zsh &&
    { [ ! -f ~/.zshrc ] || ! grep -q 'oh-my-zsh.sh' ~/.zshrc; }; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Restoring OhMyDebn's Zsh configuration"
    if [ -f ~/.zshrc ]; then
      mv ~/.zshrc ~/.zshrc-backup-"$(date +%Y%m%d-%H%M%S)"
    fi
    mv ~/.zshrc.pre-oh-my-zsh ~/.zshrc
  fi
  mkdir -p ~/.local/state/ohmydebn-config
  touch $ZSHRC_REPAIR_STATE
fi

# Oh My Zsh comes from the ohmydebn-ohmyzsh package, installed for the
# whole machine in /usr/share/oh-my-zsh (install/packaging/dependencies.sh)
# and pinned to one tested commit. It used to be downloaded into each
# user's ~/.oh-my-zsh from whatever its master branch held that day, and
# then updated itself from master every couple of weeks; config/.zshrc
# now loads the packaged copy.
#
# One-time move of an existing ~/.zshrc onto it: OhMyDebn's own ZSH line is
# replaced, and ZSH_CUSTOM keeps pointing at ~/.oh-my-zsh/custom so the
# user's own plugins and themes there still load. ~/.oh-my-zsh itself is
# left where it is, unused apart from custom/. A .zshrc with any other ZSH
# line is the user's own choice and isn't touched, nor is a symlinked one
# (a dotfiles repo's). Not marked done until the package is there, so an
# update that couldn't install it tries again next time rather than
# pointing Zsh at nothing.
OHMYZSH_PACKAGED=/usr/share/oh-my-zsh
OHMYZSH_PACKAGED_STATE=~/.local/state/ohmydebn-config/ohmyzsh-packaged-20261027
if [ ! -f $OHMYZSH_PACKAGED_STATE ] && [ -f $OHMYZSH_PACKAGED/oh-my-zsh.sh ]; then
  # shellcheck disable=SC2016 # the line as it appears in .zshrc, unexpanded
  OHMYZSH_OLD_LINE='export ZSH="$HOME/.oh-my-zsh"'
  if [ ! -L ~/.zshrc ] && grep -qxF "$OHMYZSH_OLD_LINE" ~/.zshrc 2>/dev/null; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Switching Zsh to OhMyDebn's packaged Oh My Zsh"
    # Its own suffix: the repair above can make a backup in the same second.
    cp -p ~/.zshrc ~/.zshrc-backup-"$(date +%Y%m%d-%H%M%S)"-oh-my-zsh
    ZSHRC_NEW=$(mktemp)
    # shellcheck disable=SC2016 # $HOME is written into .zshrc as is
    awk -v old="$OHMYZSH_OLD_LINE" -v dir="$OHMYZSH_PACKAGED" '
      $0 == old {
        print "export ZSH=\"" dir "\""
        print "export ZSH_CUSTOM=\"$HOME/.oh-my-zsh/custom\""
        next
      }
      { print }' ~/.zshrc >"$ZSHRC_NEW"
    # Written over the file rather than moved into place, so .zshrc keeps
    # its own permissions.
    cat "$ZSHRC_NEW" >~/.zshrc
    rm -f "$ZSHRC_NEW"
  fi
  mkdir -p ~/.local/state/ohmydebn-config
  touch $OHMYZSH_PACKAGED_STATE
fi
