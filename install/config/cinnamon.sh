#!/bin/bash

PANEL_STATE=~/.local/state/ohmydebn-panel
if [ ! -f $PANEL_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring panel to be at top of screen"
  gsettings set org.cinnamon panels-enabled "['1:0:top']"
  mkdir -p ~/.local/state
  touch $PANEL_STATE
fi

PANEL_APPLET_STATE=~/.local/state/ohmydebn-panel-applet
if [ ! -f $PANEL_APPLET_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring panel applets"
  gsettings set org.cinnamon enabled-applets "['panel1:left:0:menu@cinnamon.org:0', 'panel1:left:3:window-list@cinnamon.org:12', 'panel1:right:0:systray@cinnamon.org:3', 'panel1:right:1:xapp-status@cinnamon.org:4', 'panel1:right:2:notifications@cinnamon.org:5', 'panel1:right:3:printers@cinnamon.org:6', 'panel1:right:4:removable-drives@cinnamon.org:7', 'panel1:right:5:keyboard@cinnamon.org:8', 'panel1:right:6:favorites@cinnamon.org:9', 'panel1:right:7:network@cinnamon.org:10', 'panel1:right:8:sound@cinnamon.org:11', 'panel1:right:9:power@cinnamon.org:12', 'panel1:right:10:calendar@cinnamon.org:13', 'panel1:left:2:workspace-switcher@cinnamon.org:10']"
  touch $PANEL_APPLET_STATE
fi

WINDOW_SPEED_STATE=~/.local/state/ohmydebn-window-speed
if [ ! -f $WINDOW_SPEED_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Setting Cinnamon window effect speed to maximum"
  gsettings set org.cinnamon window-effect-speed 2
  touch $WINDOW_SPEED_STATE
fi

ALTTAB_STATE=~/.local/state/ohmydebn-alttab
if [ ! -f $ALTTAB_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring Cinnamon alttab switcher"
  gsettings set org.cinnamon alttab-switcher-style 'icons+preview'
  gsettings set org.cinnamon alttab-switcher-show-all-workspaces true
  touch $ALTTAB_STATE
fi

SPICE_STATE=~/.local/state/ohmydebn-spices
if [ ! -f $SPICE_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring Cinnamon spices"
  for SPICE in "workspace-switcher@cinnamon.org" "notifications@cinnamon.org" "calendar@cinnamon.org"; do
    SPICE_DIR=~/.config/cinnamon/spices/$SPICE
    mkdir -p $SPICE_DIR
    /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring Cinnamon spice $SPICE"
    cp -av /usr/share/ohmydebn/config/cinnamon/spices/$SPICE/* $SPICE_DIR
    echo
  done
  touch $SPICE_STATE
fi

GTILE_CONFIG_STATE=~/.local/state/ohmydebn-config/gTile-config-20250920
if [ ! -f $GTILE_CONFIG_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring gTile extension"
  SPICE_DIR=~/.config/cinnamon/spices/gTile@OhMyDebn
  mkdir -p $SPICE_DIR
  cp -av /usr/share/ohmydebn/config/cinnamon/spices/gTile@OhMyDebn/* $SPICE_DIR
  gsettings set org.cinnamon enabled-extensions "['gTile@OhMyDebn']"
  mkdir -p ~/.local/state/ohmydebn-config
  touch $GTILE_CONFIG_STATE
fi

NEMO_CONFIG_STATE=~/.local/state/ohmydebn-config/nemo-config-20250924
if [ ! -f $NEMO_CONFIG_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring nemo file manager for list view"
  gsettings set org.nemo.preferences default-folder-viewer 'list-view'
  mkdir -p ~/.local/state/ohmydebn-config
  touch $NEMO_CONFIG_STATE
fi
