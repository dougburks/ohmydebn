#!/bin/bash

# One consolidated restart for any earlier step that asked for it
# (finalization/gtile-restart-flag.sh, and config/cinnamon.sh's gTile
# checkbox fix and config/cinnamon-applet-ids.sh; the keybinding step used
# to as well, until it learned to make Cinnamon reload live) - a step sets
# OHMYDEBN_CINNAMON_RESTART_NEEDED (cleared at the top of ohmydebn.sh)
# rather than restarting immediately, so two independent restarts in the
# same run can't race each other. Done here, before the "update
# complete"/"installation complete" message below, so that message is the
# last thing printed.
# pgrep -x cinnamon here (not at flag-set time) is the up-to-date check of
# whether there's actually a live Cinnamon session to restart.
#
# In a Wayland session Cinnamon is the display server itself: cinnamon
# --replace is an X11 window manager's handover and can't restart it there,
# so a restart is left to the next login, and said so. An upgraded gTile
# needs no restart there: Cinnamon reloads just that extension
# (finalization/gtile-restart-flag.sh asks for it with
# OHMYDEBN_GTILE_RELOAD_NEEDED).
FINALE_WAYLAND=false
if [ "${XDG_SESSION_TYPE:-}" = wayland ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  FINALE_WAYLAND=true
fi
if [ "${OHMYDEBN_CINNAMON_RESTART_NEEDED:-}" = "1" ] && pgrep -x cinnamon >/dev/null; then
  if [ "$FINALE_WAYLAND" = true ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Log out and back in to apply changes"
  else
    /usr/share/ohmydebn/bin/ohmydebn-headline "Restarting Cinnamon to apply changes"
    setsid /usr/bin/cinnamon --replace >/dev/null 2>&1 &
  fi
fi
if [ "${OHMYDEBN_GTILE_RELOAD_NEEDED:-}" = "1" ] && pgrep -x cinnamon >/dev/null; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Reloading gTile"
  if ! gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon \
    --method org.Cinnamon.ReloadXlet gTile@OhMyDebn EXTENSION >/dev/null 2>&1; then
    echo "Cinnamon didn't reload it: log out and back in to use the updated gTile."
  fi
fi

# ohmydebn-reset-config (OHMYDEBN_RESET) prints its own "complete" once
# it has reapplied the theme, after this run - not "update complete".
if [ "${OHMYDEBN_RESET:-}" = "1" ]; then
  :
elif [ -f ~/.local/state/ohmydebn ]; then
  VERSION=$(/usr/share/ohmydebn/bin/ohmydebn-version)
  /usr/share/ohmydebn/bin/ohmydebn-headline "OhMyDebn update complete - version: $VERSION"
else
  echo
  /usr/share/ohmydebn/bin/ohmydebn-headline "Installation complete!"
  echo
  toilet -f mono12 "Welcome" | /usr/bin/ttfx rain
  toilet -f mono12 "   to" | /usr/bin/ttfx rain
  toilet -f mono12 "OhMyDebn" | /usr/bin/ttfx rain
  # Create a state file signifying that installation is complete
  mkdir -p ~/.local/state
  touch ~/.local/state/ohmydebn
fi

# OhMyDebn is built around the Cinnamon desktop. If the session that ran
# this install is another desktop, the user won't see any of it until they
# switch sessions at the login screen. Run over ssh or from a TTY there's no
# desktop to judge (XDG_CURRENT_DESKTOP is unset), so say nothing rather
# than tell a Cinnamon user to switch to Cinnamon.
# Two cases need a reboot instead, since LightDM only reads lightdm.conf
# when it starts and the login screen offers no session to pick: Raspberry
# Pi OS's pi-greeter, whose lightdm.conf finalization/lightdm.sh has just
# pointed at Cinnamon (seen on Raspberry Pi OS for x86 with autologin
# off), and a LightDM set to log this user straight into Cinnamon.
LIGHTDM_CONF=/etc/lightdm/lightdm.conf
if [ -n "${XDG_CURRENT_DESKTOP:-}" ] && [ "$XDG_CURRENT_DESKTOP" != "X-Cinnamon" ]; then
  echo
  if grep -qE '^[[:space:]]*greeter-session[[:space:]]*=[[:space:]]*pi-greeter' $LIGHTDM_CONF 2>/dev/null || {
    grep -qE "^[[:space:]]*autologin-user[[:space:]]*=[[:space:]]*${USER:-$(id -un)}[[:space:]]*$" $LIGHTDM_CONF 2>/dev/null &&
      grep -qE '^[[:space:]]*autologin-session[[:space:]]*=[[:space:]]*cinnamon[[:space:]]*$' $LIGHTDM_CONF
  }; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Reboot to start Cinnamon"
    echo "You're currently running $XDG_CURRENT_DESKTOP."
    echo "Reboot, and you'll start in Cinnamon from then on."
  else
    /usr/share/ohmydebn/bin/ohmydebn-headline "Log out and select Cinnamon"
    echo "You're currently running $XDG_CURRENT_DESKTOP."
    echo "Log out, then choose the Cinnamon session from your login screen before logging back in."
  fi
fi
