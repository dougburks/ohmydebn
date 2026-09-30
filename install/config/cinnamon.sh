#!/bin/bash

PANEL_STATE=~/.local/state/ohmydebn-panel
if [ ! -f $PANEL_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring panel to be at top of screen"
  gsettings set org.cinnamon panels-enabled "['1:0:top']"
  mkdir -p ~/.local/state
  touch $PANEL_STATE
fi

PANEL_APPLET_STATE=~/.local/state/ohmydebn-panel-applet
if [ ! -f $PANEL_APPLET_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring panel applets"
  gsettings set org.cinnamon enabled-applets "['panel1:left:0:menu@cinnamon.org:0', 'panel1:left:3:window-list@cinnamon.org:12', 'panel1:right:0:systray@cinnamon.org:3', 'panel1:right:1:xapp-status@cinnamon.org:4', 'panel1:right:2:notifications@cinnamon.org:5', 'panel1:right:3:printers@cinnamon.org:6', 'panel1:right:4:removable-drives@cinnamon.org:7', 'panel1:right:5:keyboard@cinnamon.org:8', 'panel1:right:6:favorites@cinnamon.org:9', 'panel1:right:7:network@cinnamon.org:10', 'panel1:right:8:sound@cinnamon.org:11', 'panel1:right:9:power@cinnamon.org:12', 'panel1:right:10:calendar@cinnamon.org:13', 'panel1:left:2:workspace-switcher@cinnamon.org:10']"
  touch $PANEL_APPLET_STATE
fi

WINDOW_SPEED_STATE=~/.local/state/ohmydebn-window-speed
if [ ! -f $WINDOW_SPEED_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Setting Cinnamon window effect speed to maximum"
  gsettings set org.cinnamon window-effect-speed 2
  touch $WINDOW_SPEED_STATE
fi

ALTTAB_STATE=~/.local/state/ohmydebn-alttab
if [ ! -f $ALTTAB_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring Cinnamon alttab switcher"
  gsettings set org.cinnamon alttab-switcher-style 'icons+preview'
  gsettings set org.cinnamon alttab-switcher-show-all-workspaces true
  touch $ALTTAB_STATE
fi

SPICE_STATE=~/.local/state/ohmydebn-spices
if [ ! -f $SPICE_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring Cinnamon spices"
  for SPICE in "workspace-switcher@cinnamon.org" "notifications@cinnamon.org" "calendar@cinnamon.org"; do
    SPICE_DIR=~/.config/cinnamon/spices/$SPICE
    mkdir -p $SPICE_DIR
    /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring Cinnamon spice $SPICE"
    cp -av /usr/share/ohmydebn/config/cinnamon/spices/$SPICE/* $SPICE_DIR
    echo
  done
  touch $SPICE_STATE
fi

GTILE_CONFIG_STATE=~/.local/state/ohmydebn-config/gTile-config-20250920
if [ ! -f $GTILE_CONFIG_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring gTile extension"
  SPICE_DIR=~/.config/cinnamon/spices/gTile@OhMyDebn
  mkdir -p $SPICE_DIR
  cp -av /usr/share/ohmydebn/config/cinnamon/spices/gTile@OhMyDebn/* $SPICE_DIR
  gsettings set org.cinnamon enabled-extensions "['gTile@OhMyDebn']"
  mkdir -p ~/.local/state/ohmydebn-config
  touch $GTILE_CONFIG_STATE
fi

# 20260926 The gTile settings seeded by 4.8.0 and earlier stored five
# checkbox defaults/values as the strings "true"/"false". gTile reads them
# raw, and in JavaScript the string "false" is truthy, so "UI always centered
# on monitor" and "Show UI on all monitors" acted as on while the settings
# dialog showed them off. The seed has real booleans now, but it's copied
# only once, so existing users' files are converted here, once. Cinnamon's
# dialog always writes real booleans, so a string was never the user's own
# choice. gTile reads its settings when it loads, so Cinnamon is restarted
# at the end of the run (finalization/finale.sh).
GTILE_BOOLEANS_STATE=~/.local/state/ohmydebn-config/gtile-booleans-20260926
GTILE_SETTINGS=~/.config/cinnamon/spices/gTile@OhMyDebn/gTile@OhMyDebn.json
if [ ! -f $GTILE_BOOLEANS_STATE ]; then
  # jq -e: 0 = some checkbox is stored as text, 1 = none is, anything else
  # = jq couldn't tell (missing, or an unreadable file) - retried next run.
  # Its status is caught with || because install.sh runs under set -e and
  # sources this, so a bare non-zero status would end the whole install.
  GTILE_BOOLEANS_CHECK=1
  if [ -f $GTILE_SETTINGS ]; then
    GTILE_BOOLEANS_CHECK=0
    jq -e 'any(.[]; type == "object" and .type == "checkbox" and
      ((.default | type) == "string" or (.value | type) == "string"))' $GTILE_SETTINGS >/dev/null 2>&1 ||
      GTILE_BOOLEANS_CHECK=$?
  fi
  if [ $GTILE_BOOLEANS_CHECK -eq 0 ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Fixing gTile checkbox settings stored as text"
    if jq 'map_values(if type == "object" and .type == "checkbox" then
          with_entries(if (.key == "default" or .key == "value") and (.value == "true" or .value == "false")
            then .value = (.value == "true") else . end)
        else . end)' $GTILE_SETTINGS >$GTILE_SETTINGS.tmp; then
      mv $GTILE_SETTINGS.tmp $GTILE_SETTINGS
      export OHMYDEBN_CINNAMON_RESTART_NEEDED=1
      GTILE_BOOLEANS_CHECK=1
    else
      rm -f $GTILE_SETTINGS.tmp
    fi
  fi
  if [ $GTILE_BOOLEANS_CHECK -eq 1 ]; then
    mkdir -p ~/.local/state/ohmydebn-config
    touch $GTILE_BOOLEANS_STATE
  fi
fi

# The ohmydebn-gtile minimum-version warning and the "restart Cinnamon if
# the installed version changed" check both live in
# install/finalization/gtile-restart-flag.sh, not here - this script runs
# as part of config/all.sh, which is sourced *before*
# finalization/updates.sh actually runs `apt upgrade` (see ohmydebn.sh's
# own packaging -> config -> cleanup -> finalization order). Checking the
# installed version here would see the OLD, pre-upgrade version - both a
# stale "out of date" warning that's already wrong by the time this run
# finishes, and (confirmed live) restarting Cinnamon before ohmydebn-gtile
# had even been upgraded that run.

NEMO_CONFIG_STATE=~/.local/state/ohmydebn-config/nemo-config-20250924
if [ ! -f $NEMO_CONFIG_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring nemo file manager for list view"
  gsettings set org.nemo.preferences default-folder-viewer 'list-view'
  mkdir -p ~/.local/state/ohmydebn-config
  touch $NEMO_CONFIG_STATE
fi

IBUS_PANEL_STATE=~/.local/state/ohmydebn-config/ibus-panel-20260828
if [ ! -f $IBUS_PANEL_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Hiding the ibus systray icon"
  # ibus isn't an ohmydebn dependency - it only shows up because it ships on
  # the Debian Cinnamon ISO. On other bases (e.g. Kali, which defaults to
  # XFCE) its schema is absent, so `|| true` keeps this line from aborting
  # the rest of the install under the caller's `set -e`.
  gsettings set org.freedesktop.ibus.panel show-icon-on-systray false || true
  mkdir -p ~/.local/state/ohmydebn-config
  touch $IBUS_PANEL_STATE
fi

CLOCK_FORMAT_STATE=~/.local/state/ohmydebn-config/clock-format-20260828
if [ ! -f $CLOCK_FORMAT_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Setting clock to 12-hour format"
  gsettings set org.cinnamon.desktop.interface clock-use-24h false
  mkdir -p ~/.local/state/ohmydebn-config
  touch $CLOCK_FORMAT_STATE
fi
