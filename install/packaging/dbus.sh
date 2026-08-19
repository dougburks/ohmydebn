#!/bin/bash

if [ -f /usr/bin/pveversion ] && ! dpkg -s dbus-x11 >/dev/null 2>&1; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Installing dbus-x11"
  sudo /usr/bin/apt -y install dbus-x11
  eval "$(dbus-launch --sh-syntax)"
fi
