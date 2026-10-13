#!/bin/bash

# OHMYDEBN_CINNAMON_RESTART_NEEDED is cleared once at the top of
# ohmydebn.sh, not here: config steps set it too (gTile's checkbox fix,
# the applet ID fix), and clearing it here threw their requests away.

source $OHMYDEBN_INSTALL/finalization/updates.sh
source $OHMYDEBN_INSTALL/finalization/theme-carousel-cache.sh
source $OHMYDEBN_INSTALL/finalization/gtile-restart-flag.sh
source $OHMYDEBN_INSTALL/finalization/keybinding.sh
source $OHMYDEBN_INSTALL/finalization/lightdm.sh
source $OHMYDEBN_INSTALL/finalization/default-session.sh
source $OHMYDEBN_INSTALL/finalization/finale.sh
source $OHMYDEBN_INSTALL/finalization/reboot-notice.sh
