#!/bin/bash

# The OhMyDebn Menu gets its own button on the panel, right after the
# Cinnamon menu (4.12.0). Runs after menu.sh, which writes the
# ohmydebn-menu.desktop the button launches. Once only, so a user who
# removes the button doesn't get it back on the next update. The marker is
# set only when the panel could be read, so a run without a desktop
# session (no session bus) tries again next time.
PANEL_MENU_LAUNCHER_STATE=~/.local/state/ohmydebn-config/panel-menu-launcher-20261016
if [ ! -f $PANEL_MENU_LAUNCHER_STATE ]; then
  if /usr/share/ohmydebn/bin/ohmydebn-panel-menu-launcher; then
    mkdir -p ~/.local/state/ohmydebn-config
    touch $PANEL_MENU_LAUNCHER_STATE
  fi
fi
