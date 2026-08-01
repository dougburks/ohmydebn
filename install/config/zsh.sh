#!/bin/bash

SOUNDS_STATE=~/.local/state/ohmydebn-config/sounds-20260801
if [ ! -f $SOUNDS_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Disabling system sounds"
  gsettings set org.cinnamon.sounds close-enabled false
  gsettings set org.cinnamon.sounds login-enabled false
  gsettings set org.cinnamon.sounds logout-enabled false
  gsettings set org.cinnamon.sounds map-enabled false
  gsettings set org.cinnamon.sounds maximize-enabled false
  gsettings set org.cinnamon.sounds minimize-enabled false
  gsettings set org.cinnamon.sounds notification-enabled false
  gsettings set org.cinnamon.sounds plug-enabled false
  gsettings set org.cinnamon.sounds switch-enabled false
  gsettings set org.cinnamon.sounds tile-enabled false
  gsettings set org.cinnamon.sounds unmaximize-enabled false
  gsettings set org.cinnamon.sounds unplug-enabled false
  gsettings set org.cinnamon.desktop.sound volume-sound-enabled false
  touch $SOUNDS_STATE
fi
