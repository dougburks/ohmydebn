#!/bin/bash

LIGHTDM_CONF=/etc/lightdm/lightdm.conf
if grep "rpd-labwc" $LIGHTDM_CONF >/dev/null 2>&1; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Updating $LIGHTDM_CONF to log into cinnamon desktop"
  echo "Once installation is complete, you will need to reboot to make this change take effect."
  # The original is backed up once: default-session.sh edits this file too,
  # and a later edit must not replace the original with an edited copy.
  if [ ! -e "$LIGHTDM_CONF.BEFORE.OHMYDEBN" ]; then
    sudo cp -p "$LIGHTDM_CONF" "$LIGHTDM_CONF.BEFORE.OHMYDEBN"
  fi
  sudo sed -i 's|rpd-labwc|cinnamon|g' $LIGHTDM_CONF
fi
