#!/bin/bash

if [ ! -f ~/.local/share/fonts/CaskaydiaMonoNerdFont-Regular.ttf ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring Caskaydia Nerd Font"
  wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CascadiaMono.zip
  unzip CascadiaMono.zip -d ~/.local/share/fonts
  rm -f CascadiaMono.zip
  fc-cache -fv
fi
