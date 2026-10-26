#!/bin/bash

# Omarchy's intro clips for its themes (the ohmydebn-themes-omarchy-intros
# package; every other background gets the light intro drawn live) are
# installed once - on a new
# install, or on the update that first offers them - and not on a Raspberry
# Pi, where they never play (see ohmydebn-theme-intro). Once, because the
# package is tens of megabytes: someone who removes it to save the space
# keeps it removed through later updates. The machine-wide marker records
# that it was installed (or deliberately skipped), so a run where the
# package couldn't be installed - not yet in the repo, the network down -
# tries again next time.
THEME_INTROS_STATE_DIR=/var/lib/ohmydebn
THEME_INTROS_STATE=$THEME_INTROS_STATE_DIR/theme-intros-offered
THEME_INTROS_PACKAGE=ohmydebn-themes-omarchy-intros
THEME_INTROS_MODEL="${OHMYDEBN_TEST_DEVICE_TREE_MODEL:-/proc/device-tree/model}"
if [ ! -f $THEME_INTROS_STATE ]; then
  # -r first: only some machines (a Raspberry Pi among them) have the
  # file, and a redirect from a missing one prints its own error.
  if [ -r "$THEME_INTROS_MODEL" ] && tr -d '\0' <"$THEME_INTROS_MODEL" | grep -q 'Raspberry Pi'; then
    sudo mkdir -p $THEME_INTROS_STATE_DIR
    sudo touch $THEME_INTROS_STATE
  else
    /usr/share/ohmydebn/bin/ohmydebn-headline "Installing theme intros"
    /usr/share/ohmydebn/bin/ohmydebn-pkg-install-optional $THEME_INTROS_PACKAGE || true
    if dpkg -s $THEME_INTROS_PACKAGE >/dev/null 2>&1; then
      sudo mkdir -p $THEME_INTROS_STATE_DIR
      sudo touch $THEME_INTROS_STATE
    fi
  fi
fi
