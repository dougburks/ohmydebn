#!/bin/bash

for DIR in ohmydebn omarchy; do
  FULL_DIR=~/.local/share/$DIR
  if [ -d $FULL_DIR ]; then
    echo "Removing old directory $FULL_DIR"
    rm -rf $FULL_DIR
  fi
done
