#!/bin/bash

if [ ! -d ~/.config/opencode ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring opencode"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/opencode ~/.config/
  echo
fi
