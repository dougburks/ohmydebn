#!/bin/bash

# The firewall is one setting for the whole machine, so whether OhMyDebn
# has set it up is recorded machine-wide too. It used to be recorded only
# in each user's home, so a second user's first install or update turned
# the firewall back on even if someone had deliberately turned it off.
# A user's old marker (UFW_STATE) means the machine was already set up:
# the machine-wide marker is written and nothing else changes.
UFW_STATE=~/.local/state/ohmydebn-ufw
UFW_SYSTEM_STATE_DIR=/var/lib/ohmydebn
UFW_SYSTEM_STATE=$UFW_SYSTEM_STATE_DIR/ufw-configured
if [ ! -f $UFW_SYSTEM_STATE ]; then
  if [ ! -f $UFW_STATE ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring firewall to deny inbound connections"
    sudo ufw enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
  fi
  sudo mkdir -p $UFW_SYSTEM_STATE_DIR
  sudo touch $UFW_SYSTEM_STATE
fi
