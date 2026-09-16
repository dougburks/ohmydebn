#!/bin/bash

# SLiM - Devuan's default login manager - has no session menu and no
# per-user memory: F1 cycles /usr/share/xsessions for one login only, and
# with nothing chosen it hands an empty session to /etc/X11/Xsession, which
# falls through to the x-session-manager alternative. cinnamon-session and
# startxfce4 both register that alternative at priority 50, and on a tie
# update-alternatives keeps whichever was installed first - XFCE, on a
# Devuan desktop install - so without this step every plain login after
# OhMyDebn lands back in XFCE. Pin the alternative to cinnamon-session
# instead; F1 still lets someone pick XFCE for a single session, and
# `update-alternatives --auto x-session-manager` undoes this.
#
# LightDM/GDM/SDDM have their own session pickers and remember the choice,
# so this is deliberately SLiM-only.
DEFAULT_DM_FILE=/etc/X11/default-display-manager
CINNAMON_SESSION=/usr/bin/cinnamon-session
if grep -qx '/usr/bin/slim' $DEFAULT_DM_FILE 2>/dev/null && [ -x $CINNAMON_SESSION ]; then
  CURRENT_SESSION_MANAGER=$(update-alternatives --query x-session-manager 2>/dev/null | sed -n 's/^Value: //p')
  if [ "$CURRENT_SESSION_MANAGER" != "$CINNAMON_SESSION" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Setting Cinnamon as the default login session for SLiM"
    echo "SLiM has no session menu, so plain logins would otherwise keep starting the previous desktop."
    echo "To start a different desktop for one login, press F1 at the SLiM login screen."
    sudo update-alternatives --set x-session-manager $CINNAMON_SESSION
  fi
fi
