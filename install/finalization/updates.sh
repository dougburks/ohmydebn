#!/bin/bash

/usr/share/ohmydebn/bin/ohmydebn-headline "tte rain" "Installing any available package updates"
sudo apt update && sudo apt -y full-upgrade
