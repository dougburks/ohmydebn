#!/bin/bash

STATE_DIR=~/.local/state/ohmydebn-config
KEYBINDING_STATE=$STATE_DIR/keybinding-20260822

if [ ! -f $KEYBINDING_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Updating hotkeys"

  KEYBINDING_DIR=/usr/share/ohmydebn/install/keybinding
  KEYBINDING_CINNAMON=$KEYBINDING_DIR/keybinding-cinnamon.txt
  KEYBINDING_CUSTOM=$KEYBINDING_DIR/keybinding-custom.txt

  function keybinding-cinnamon() {
    local CMD
    echo "$4"
    CMD="gsettings set org.cinnamon.desktop.keybindings.$1 $2 \"$3\""
    eval "$CMD"
  }

  function keybinding-custom() {
    local GSETTINGS1 GSETTINGS2 GSETTINGS3
    echo "$5"
    GSETTINGS1="gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/ name \"$2\""
    GSETTINGS2="gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/ command \"$3\""
    GSETTINGS3="gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/ binding \"$4\""
    eval "$GSETTINGS1"
    eval "$GSETTINGS2"
    eval "$GSETTINGS3"
  }

  # To create new custom keybindings, first specify how many custom keybindings we're going to load
  CUSTOM_KEYBINDING_TOTAL=$(cat $KEYBINDING_CUSTOM | wc -l)
  # Not `let CUSTOM_KEYBINDING_TOTAL--` - `let`/`((...))` exit non-zero when
  # the resulting expression value is 0, which would abort the whole install
  # under the caller's `set -e` if the custom-keybindings count were ever 0.
  # Plain arithmetic assignment doesn't have that pitfall.
  CUSTOM_KEYBINDING_TOTAL=$((CUSTOM_KEYBINDING_TOTAL - 1))
  CUSTOM_LIST="gsettings set org.cinnamon.desktop.keybindings custom-list \"["
  for i in $(seq 0 $CUSTOM_KEYBINDING_TOTAL); do
    CUSTOM_LIST+="'custom-$i'"
    if [ "$i" != "$CUSTOM_KEYBINDING_TOTAL" ]; then
      CUSTOM_LIST+=", "
    else
      CUSTOM_LIST+="]\""
    fi
  done
  eval "$CUSTOM_LIST"

  # Update all keybindings and sort the output for display
  (
    # shellcheck source=keybinding-cinnamon.txt
    source "$KEYBINDING_CINNAMON"
    # shellcheck source=keybinding-custom.txt
    source "$KEYBINDING_CUSTOM"
  ) | grep -v "Removing" | sort

  # Apply keybindings
  if pgrep -x cinnamon >/dev/null; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Restarting desktop to apply hotkey configuration"
    sleep 1s
    setsid /usr/bin/cinnamon --replace >/dev/null 2>&1 &
    echo "You can see all hotkeys by pressing Super + K"
  fi

  mkdir -p $STATE_DIR
  touch $KEYBINDING_STATE
fi
