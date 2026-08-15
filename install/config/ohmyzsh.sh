#!/bin/bash

if ! dpkg -s "zsh" >/dev/null 2>&1; then
  exit 0
fi

OHMYZSH_DIR=~/.oh-my-zsh
if [ ! -d $OHMYZSH_DIR ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Installing Oh My Zsh framework for Zsh"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  mv ~/.zshrc ~/.zshrc.oh-my-zsh
fi
