#!/bin/bash

if [ -f ~/.local/share/fonts/CaskaydiaMonoNerdFont-Regular.ttf ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Cleaning up old fonts"
  rm -f ~/.local/share/fonts/CaskaydiaMonoNerdFont*
fi
