#!/bin/bash

# If packages haven't been installed yet, then install them. Keep this: it's
# how installs from before OhMyDebn was a package (Nov 2025, a git clone in
# ~/.local/share/ohmydebn) move onto the package. Their old ohmydebn-update
# runs `git pull` on that checkout and then this file from it, so this is
# the new code they get: it runs the checkout's install.sh, which adds the
# apt repo and installs the ohmydebn package (install/cleanup/local-share.sh
# then removes the old checkout). Never reached on a packaged install.
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

# Steps that need Cinnamon restarted (to load an upgraded gTile, or a panel
# or extension setting it only reads at startup) set this instead of
# restarting it themselves, and finalization/finale.sh does the one restart
# at the end. Cleared here, before any step runs, so a value left in the
# environment never causes a restart nothing asked for, while a request
# from a config step still reaches finale.sh.
unset OHMYDEBN_CINNAMON_RESTART_NEEDED

# Packaging
source $OHMYDEBN_INSTALL/packaging/all.sh

# Config
source $OHMYDEBN_INSTALL/config/all.sh

# Cleanup
source $OHMYDEBN_INSTALL/cleanup/all.sh

# Finalization
source $OHMYDEBN_INSTALL/finalization/all.sh
