#!/bin/bash

SPICE_VDAGENT_STATE=~/.local/state/ohmydebn-config/spice-vdagent-20260803
if [ ! -f $SPICE_VDAGENT_STATE ]; then

  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Making sure that the correct version of spice-vdagent is installed"
  # Debian Forky (and its derivates like Kali) includes a newer version of spice-vdagent.
  # This newer version has a regression where it won't resize the screen properly.
  # We need to force them to downgrade to the working version.
  sudo /usr/bin/apt -y install spice-vdagent=0.22.1-4.1 --allow-downgrades

  mkdir -p ~/.local/state/ohmydebn-config
  touch $SPICE_VDAGENT_STATE
fi
