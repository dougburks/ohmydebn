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

# The AI Assistant (Super + A) gets a button right after the OhMyDebn
# Menu's, in the same panel launcher (4.18.0). New installs get both from
# the step above; this adds it for installs that got the OhMyDebn Menu
# button before it existed, and does nothing where the OhMyDebn Menu button
# was removed or the AI button is already there. Once only, with the same
# marker rule as above, so a user who removes it doesn't get it back.
PANEL_AI_LAUNCHER_STATE=~/.local/state/ohmydebn-config/panel-ai-launcher-20261113
if [ ! -f $PANEL_AI_LAUNCHER_STATE ]; then
  if /usr/share/ohmydebn/bin/ohmydebn-panel-menu-launcher --add-ai; then
    mkdir -p ~/.local/state/ohmydebn-config
    touch $PANEL_AI_LAUNCHER_STATE
  fi
fi
