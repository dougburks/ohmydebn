#!/bin/bash

DIR=~/.local/share/applications
mkdir -p $DIR
MENU=$DIR/ohmydebn-menu.desktop

# The icon ships in the ohmydebn package (hicolor theme). It's symbolic, so
# the menu and panel tint it with the theme's text color, like Cinnamon's
# own panel icons.
if [ ! -f $MENU ]; then
  cat <<EOF >>$MENU
[Desktop Entry]
Version=1.0
Name=OhMyDebn Menu
Comment=OhMyDebn Menu
Exec=/usr/share/ohmydebn/bin/ohmydebn-menu
Terminal=false
Type=Application
Icon=ohmydebn-menu-symbolic
StartupNotify=true
EOF
fi

# Launchers written before 4.12.0 used stock_smiley-1, which comes from an
# icon theme that LMDE 7 doesn't install, so it showed no icon
# there. Only that exact old default is replaced: an icon the user picked
# stays.
if grep -qx 'Icon=stock_smiley-1' $MENU; then
  sed -i 's/^Icon=stock_smiley-1$/Icon=ohmydebn-menu-symbolic/' $MENU
fi
