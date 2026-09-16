#!/bin/bash

# Make Cinnamon the default login session, so a plain login after install
# starts Cinnamon rather than whatever desktop the base image shipped
# (XFCE on Devuan/LCOS). Two layers, because display managers differ:
#
# 1. The x-session-manager alternative. SLiM (Devuan's default login
#    manager) has no session menu and no memory: F1 cycles sessions for a
#    single login, and with nothing chosen /etc/X11/Xsession falls through
#    to this alternative. LightDM's "Default Xsession" entry runs the same
#    thing. cinnamon-session and startxfce4 both register at priority 50,
#    and on a tie update-alternatives keeps whichever was installed first,
#    so on an XFCE base that stays XFCE. Pin cinnamon-session instead;
#    `update-alternatives --auto x-session-manager` undoes this.
#
# 2. LightDM's user-session. LightDM starts a user's remembered session
#    (accountsservice / ~/.dmrc) when there is one, else user-session. A
#    drop-in in lightdm.conf.d sets that default for anyone with nothing
#    remembered yet. lightdm.conf itself loads after the drop-ins and would
#    win, so an explicit non-cinnamon user-session there is switched too,
#    with a .BEFORE.OHMYDEBN backup like finalization/lightdm.sh's RPi edit.
#
# Neither layer touches an existing user's remembered session: someone who
# has already logged into XFCE under LightDM picks Cinnamon once from the
# greeter's session menu, and LightDM remembers it from then on.
DEFAULT_DM_FILE=/etc/X11/default-display-manager
CINNAMON_SESSION=/usr/bin/cinnamon-session
LIGHTDM_DIR=/etc/lightdm
LIGHTDM_CONF=$LIGHTDM_DIR/lightdm.conf
LIGHTDM_DROPIN=$LIGHTDM_DIR/lightdm.conf.d/50-ohmydebn-session.conf

if [ -x $CINNAMON_SESSION ]; then
  CURRENT_SESSION_MANAGER=$(update-alternatives --query x-session-manager 2>/dev/null | sed -n 's/^Value: //p')
  if [ "$CURRENT_SESSION_MANAGER" != "$CINNAMON_SESSION" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Setting Cinnamon as the default login session"
    if grep -qx '/usr/bin/slim' $DEFAULT_DM_FILE 2>/dev/null; then
      echo "SLiM has no session menu, so plain logins would otherwise keep starting the previous desktop."
      echo "To start a different desktop for one login, press F1 at the SLiM login screen."
    fi
    sudo update-alternatives --set x-session-manager $CINNAMON_SESSION
  fi

  if [ -d $LIGHTDM_DIR ]; then
    DROPIN_CONTENT="[Seat:*]
user-session=cinnamon"
    if [ ! -f $LIGHTDM_DROPIN ] || [ "$(cat $LIGHTDM_DROPIN)" != "$DROPIN_CONTENT" ]; then
      /usr/share/ohmydebn/bin/ohmydebn-headline "Setting Cinnamon as LightDM's default session"
      sudo mkdir -p "$(dirname $LIGHTDM_DROPIN)"
      echo "$DROPIN_CONTENT" | sudo tee $LIGHTDM_DROPIN >/dev/null
    fi
    # Only an active (uncommented) user-session line that isn't already
    # cinnamon needs changing - lightdm.conf ships with it commented out.
    if grep -qE '^[[:space:]]*user-session[[:space:]]*=' $LIGHTDM_CONF 2>/dev/null &&
      ! grep -qE '^[[:space:]]*user-session[[:space:]]*=[[:space:]]*cinnamon[[:space:]]*$' $LIGHTDM_CONF; then
      echo "Updating user-session in $LIGHTDM_CONF, which would otherwise override the LightDM drop-in."
      sudo sed -i.BEFORE.OHMYDEBN -E 's/^([[:space:]]*user-session[[:space:]]*=).*/\1cinnamon/' $LIGHTDM_CONF
    fi
  fi
fi
