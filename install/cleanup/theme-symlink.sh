#!/bin/bash

# Some installs might have an incorrect symlink that needs to be removed
OLD_SYMLINK=/opt/ohmydebn/themes/ohmydebn/ohmydebn
if [ -L $OLD_SYMLINK ]; then
  echo "Removing old symlink $OLD_SYMLINK"
  rm -f $OLD_SYMLINK
fi
