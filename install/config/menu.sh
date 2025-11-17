#!/bin/bash

DIR=~/.local/share/applications
mkdir -p $DIR
MENU=$DIR/ohmydebn-menu.desktop

if [ ! -f $MENU ]; then
  cat <<EOF >>$MENU
[Desktop Entry]
Version=1.0
Name=OhMyDebn Menu
Comment=OhMyDebn Menu
Exec=/usr/share/ohmydebn/bin/ohmydebn-menu
Terminal=false
Type=Application
Icon=stock_smiley-1
StartupNotify=true
EOF
fi
