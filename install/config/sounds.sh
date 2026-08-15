#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Adjusting desktop sounds"
  /usr/bin/gsettings set org.cinnamon.desktop.sound volume-sound-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds close-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds login-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds logout-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds map-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds maximize-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds minimize-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds notification-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds plug-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds switch-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds tile-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds unmaximize-enabled false
  /usr/bin/gsettings set org.cinnamon.sounds unplug-enabled false
fi
