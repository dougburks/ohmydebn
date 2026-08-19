#!/bin/bash

# install
# cinnamon.sh prints the introductory "Configuring base OS" banner and must
# run first, before any package installs below.
source $OHMYDEBN_INSTALL/packaging/cinnamon.sh

# dbus.sh and spice-vdagent.sh each need their package installed immediately
# (dbus.sh calls dbus-launch right after installing dbus-x11; spice-vdagent.sh
# installs and pins a specific version), so they run their own direct
# `apt install` rather than participating in dependencies.sh's batched
# install.
source $OHMYDEBN_INSTALL/packaging/dbus.sh
source $OHMYDEBN_INSTALL/packaging/spice-vdagent.sh

source $OHMYDEBN_INSTALL/packaging/dependencies.sh

# power-user.sh must run after dependencies.sh above (see the comment in
# that file for why).
source $OHMYDEBN_INSTALL/packaging/power-user.sh
