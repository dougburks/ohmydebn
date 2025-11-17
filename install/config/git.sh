#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring git"
  # Set common git aliases
  git config --global alias.co checkout
  git config --global alias.br branch
  git config --global alias.ci commit
  git config --global alias.st status
fi
