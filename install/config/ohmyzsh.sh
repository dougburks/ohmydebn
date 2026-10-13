#!/bin/bash

if ! dpkg -s "zsh" >/dev/null 2>&1; then
  return 0
fi

OHMYZSH_DIR=~/.oh-my-zsh
if [ ! -d $OHMYZSH_DIR ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Installing Oh My Zsh framework for Zsh"
  # A failed download must not stop the install: sh -c "" succeeds on an
  # empty script, and the mv after it then failed on the missing ~/.zshrc,
  # stopping every update until the download worked. Without Oh My Zsh the
  # next update tries again (and ohmydebn-doctor reports it meanwhile).
  OHMYZSH_INSTALLER=$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) || OHMYZSH_INSTALLER=""
  # --keep-zshrc: a ~/.zshrc that's already there stays. Without it the
  # installer moved it to ~/.zshrc.pre-oh-my-zsh and wrote its template,
  # which the mv below then moved away too - so when the first install's
  # download had failed and a later update's worked, OhMyDebn's own .zshrc
  # (written by zsh.sh in between) was lost, and with it Starship and the
  # aliases. Only a template the installer wrote here is moved aside;
  # zsh.sh puts OhMyDebn's in place.
  ZSHRC_EXISTED=false
  if [ -e ~/.zshrc ] || [ -L ~/.zshrc ]; then
    ZSHRC_EXISTED=true
  fi
  if [ -n "$OHMYZSH_INSTALLER" ] && sh -c "$OHMYZSH_INSTALLER" "" --unattended --keep-zshrc; then
    if [ "$ZSHRC_EXISTED" = false ] && [ -f ~/.zshrc ]; then
      mv ~/.zshrc ~/.zshrc.oh-my-zsh
    fi
  else
    echo "Couldn't install Oh My Zsh. The next OhMyDebn update will try again."
  fi
fi

# One-time repair for installs that hit the bug above before it was fixed:
# OhMyDebn's .zshrc sits at ~/.zshrc.pre-oh-my-zsh, and ~/.zshrc holds only
# the PATH lines zsh.sh appends. Put OhMyDebn's back (keeping the stub as a
# backup), recognized by the Starship line only OhMyDebn's .zshrc has.
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
