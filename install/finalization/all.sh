#!/bin/bash

# Clear any pre-existing value before gtile-restart-flag.sh/hotkeys.sh
# below get a chance to set it - under the normal ohmydebn-update
# invocation (a fresh `bash install.sh` subprocess each run) this can
# never actually be set yet at this point, so this is a no-op in
# practice; it exists so that stays true even if something ever invokes
# this flow differently (e.g. `source install.sh` directly instead of
# running it as its own process, for faster local iteration) - without
# this, a leftover exported "1" from an earlier run in the same shell
# would trigger an unnecessary restart even when nothing this run
# actually needs one.
unset OHMYDEBN_CINNAMON_RESTART_NEEDED

source $OHMYDEBN_INSTALL/finalization/updates.sh
source $OHMYDEBN_INSTALL/finalization/gtile-restart-flag.sh
source $OHMYDEBN_INSTALL/finalization/hotkeys.sh
source $OHMYDEBN_INSTALL/finalization/lightdm.sh
source $OHMYDEBN_INSTALL/finalization/finale.sh
