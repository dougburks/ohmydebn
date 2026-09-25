#!/bin/bash

# If packages haven't been installed yet, then install them
if ! dpkg -s "ohmydebn" >/dev/null 2>&1; then
  ~/.local/share/ohmydebn/install.sh
  exit
fi

# Our packages install to /usr/share/
OHMYDEBN_INSTALL=/usr/share/ohmydebn/install

# Every gsettings/dconf write below is for Cinnamon, which reads the default
# dconf profile (~/.config/dconf/user). A desktop session can point
# DCONF_PROFILE somewhere else: Pop!_OS's COSMIC exports DCONF_PROFILE=cosmic,
# whose profile writes to ~/.config/dconf/cosmic first. Installed from inside
# COSMIC, every setting landed there, where Cinnamon never looks, while each
# step's one-time state marker was still written - so the panel, applets and
# the rest stayed at Cinnamon's defaults and nothing ever retried.
unset DCONF_PROFILE

# Packaging
source $OHMYDEBN_INSTALL/packaging/all.sh

# Config
source $OHMYDEBN_INSTALL/config/all.sh

# Cleanup
source $OHMYDEBN_INSTALL/cleanup/all.sh

# Finalization
source $OHMYDEBN_INSTALL/finalization/all.sh
