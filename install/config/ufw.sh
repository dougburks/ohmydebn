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
#
# Over SSH, `ufw enable` asks whether to go ahead, since it may cut off the
# connection, and on anything but y it prints "Aborted" and still exits 0.
# So the marker is written only once the firewall is actually on: an
# install over SSH that didn't turn it on tries again on the next update
# instead of leaving the machine without a firewall for good.
if [ ! -f $UFW_SYSTEM_STATE ]; then
  UFW_ON=true
  if [ ! -f $UFW_STATE ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring firewall to deny inbound connections"
    sudo ufw enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    UFW_STATUS=$(sudo ufw status 2>/dev/null || true)
    if [[ "$UFW_STATUS" != *"Status: active"* ]]; then
      UFW_ON=false
      echo "The firewall wasn't turned on. The next update will try again, or turn it on now with: sudo ufw enable"
    fi
  fi
  if [ "$UFW_ON" = true ]; then
    sudo mkdir -p $UFW_SYSTEM_STATE_DIR
    sudo touch $UFW_SYSTEM_STATE
  fi
fi
