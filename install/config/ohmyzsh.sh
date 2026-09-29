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
  if [ -n "$OHMYZSH_INSTALLER" ] && sh -c "$OHMYZSH_INSTALLER" "" --unattended; then
    # The installer writes its own ~/.zshrc; zsh.sh puts OhMyDebn's in place.
    if [ -f ~/.zshrc ]; then
      mv ~/.zshrc ~/.zshrc.oh-my-zsh
    fi
  else
    echo "Couldn't install Oh My Zsh. The next OhMyDebn update will try again."
  fi
fi
