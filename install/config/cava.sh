#!/bin/bash

if [ ! -d ~/.config/cava ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Configuring cava"
  mkdir -p ~/.config
  cp -av /opt/ohmydebn/config/cava ~/.config/
  echo
fi
