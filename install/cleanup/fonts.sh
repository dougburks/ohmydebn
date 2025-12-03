#!/bin/bash

DIR=~/.local/share/fonts
if [ -f $DIR/CaskaydiaMonoNerdFont-Regular.ttf ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Cleaning up $DIR"
  rm -f $DIR/CaskaydiaMonoNerdFont*
  rm -f $DIR/LICENSE
  rm -f $DIR/README.md
fi
