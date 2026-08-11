#!/bin/bash

SPICE_VDAGENT_STATE=~/.local/state/ohmydebn-config/spice-vdagent-20260803
if [ ! -f $SPICE_VDAGENT_STATE ]; then

  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Making sure that the correct version of spice-vdagent is installed"

  # Debian Forky includes a newer version of spice-vdagent.
  # This newer version has a regression where it won't resize the screen properly.
  # We need to force a downgrade to the working version.
  sudo /usr/bin/apt -y install spice-vdagent=0.22.1-4.1 --allow-downgrades

  # Next we need to pin the version so that it can't be updated later
  sudo mkdir -p /etc/apt/preferences.d/
  sudo tee /etc/apt/preferences.d/ohmydebn-spice-vdagent >/dev/null <<'EOF'
Package: spice-vdagent
Pin: version 0.22.1-4.1
Pin-Priority: 1001
EOF

  # Set permissions on the file
  sudo chmod 644 /etc/apt/preferences.d/ohmydebn-spice-vdagent

  # Finally, touch the state file so that we don't run this code on every update.
  mkdir -p ~/.local/state/ohmydebn-config
  touch $SPICE_VDAGENT_STATE
fi
