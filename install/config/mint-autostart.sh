#!/bin/bash

# Linux Mint autostarts a handful of its own apps that either duplicate
# something OhMyDebn already provides its own way (Warpinator vs. the
# LocalSend hotkey/menu entry) or just add unrequested noise on first
# login (mintwelcome's tour, mintupdate/mintreport's update/crash nags,
# Sticky Notes popping up unasked). Disabling via a per-user override in
# ~/.config/autostart/ - the standard XDG mechanism, and exactly what
# Cinnamon's own "Startup Applications" settings panel does when you
# toggle an entry off - rather than touching the system-wide
# /etc/xdg/autostart/ file directly, so it stays reversible (the user can
# just delete the override, or re-enable it from that same settings
# panel) and doesn't affect other accounts on the same machine.
#
# Only ever runs once: if the user later re-enables one of these
# themselves, a subsequent ohmydebn-update must not silently turn it back
# off underneath them.
if [ "$ID" = "linuxmint" ]; then
  MINT_AUTOSTART_STATE=~/.local/state/ohmydebn-config/mint-autostart-20260902
  if [ ! -f "$MINT_AUTOSTART_STATE" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Disabling unneeded Mint autostart apps"
    mkdir -p ~/.config/autostart
    for NAME in mintupdate mintreport mintwelcome warpinator-autostart sticky; do
      if [ -f "/etc/xdg/autostart/$NAME.desktop" ]; then
        printf '[Desktop Entry]\nType=Application\nHidden=true\n' >~/.config/autostart/"$NAME".desktop
      fi
    done
    mkdir -p ~/.local/state/ohmydebn-config
    touch "$MINT_AUTOSTART_STATE"
  fi
fi
