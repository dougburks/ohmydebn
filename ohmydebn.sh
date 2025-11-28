#!/bin/bash

# If packages haven't been installed yet, then install them
if ! dpkg -s "ohmydebn" >/dev/null 2>&1; then
  ~/.local/share/ohmydebn/install.sh --no-uninstall
  exit
fi

# Our packages install to /usr/share/
OHMYDEBN_INSTALL=/usr/share/ohmydebn/install

# Packaging
source $OHMYDEBN_INSTALL/packaging/all.sh

# Config
source $OHMYDEBN_INSTALL/config/all.sh

# Cleanup
source $OHMYDEBN_INSTALL/cleanup/all.sh

# Finalization
source $OHMYDEBN_INSTALL/finalization/all.sh
