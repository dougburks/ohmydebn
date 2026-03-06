#!/bin/bash

/usr/share/ohmydebn/bin/ohmydebn-headline "tte rain" "Installing any available package updates"
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
echo
/usr/share/ohmydebn/bin/ohmydebn-update-opencode 1.2.20
