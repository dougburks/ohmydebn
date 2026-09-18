#!/bin/bash

# Brave Origin is the default browser for new installs (install/packaging/
# browser.sh); Chromium is what installs before that switch got, and what
# browser.sh falls back to when Brave Origin can't be installed. Whichever
# is present is the one to configure, Brave Origin first.
#
# Brave's package registers /usr/bin/brave-origin-stable itself as an
# x-www-browser and gnome-www-browser alternative (priority 201), so that
# exact path is the one to select below - /usr/bin/brave-origin is a further
# alternatives symlink on top of it and would register as a second entry.
#
# Ubuntu has no "chromium" apt package (see bin/ohmydebn-chromium-install) -
# it only ever gets chromium as a strictly-confined snap, which has no
# /usr/bin/chromium at all. The real binary is /snap/bin/chromium (itself a
# symlink into snapd's own command dispatcher, not a broken link), and its
# desktop file is registered under snapd's own naming scheme rather than
# plain "chromium.desktop". Confirmed working end-to-end - update-
# alternatives, xdg-settings, xdg-mime, and an actual xdg-open launch - on
# Ubuntu 24.04/26.04 with Cinnamon.
if dpkg -s brave-origin >/dev/null 2>&1; then
  BROWSER_NAME="Brave Origin"
  BROWSER_BIN=/usr/bin/brave-origin-stable
  BROWSER_DESKTOP=brave-origin.desktop
elif dpkg -s chromium >/dev/null 2>&1; then
  BROWSER_NAME=chromium
  BROWSER_BIN=/usr/bin/chromium
  BROWSER_DESKTOP=chromium.desktop
elif snap list chromium >/dev/null 2>&1; then
  BROWSER_NAME=chromium
  BROWSER_BIN=/snap/bin/chromium
  BROWSER_DESKTOP=chromium_chromium.desktop
fi

if [ ! -f ~/.local/state/ohmydebn ]; then
  if [ -n "$BROWSER_BIN" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring $BROWSER_NAME as default web browser"
    sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser "$BROWSER_BIN" 200 || true
    sudo update-alternatives --set x-www-browser "$BROWSER_BIN" || true
    sudo update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser "$BROWSER_BIN" 200 || true
    sudo update-alternatives --set gnome-www-browser "$BROWSER_BIN" || true
    xdg-settings set default-web-browser "$BROWSER_DESKTOP" || true
    xdg-mime default "$BROWSER_DESKTOP" x-scheme-handler/http || true
    xdg-mime default "$BROWSER_DESKTOP" x-scheme-handler/https || true
  fi

  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring ristretto as default image viewer"
  xdg-mime default org.xfce.ristretto.desktop image/bmp image/gif image/jpeg image/png image/tiff image/webp
fi

# Existing installs already carry this marker, so their PDF handler stays
# whatever it is (chromium) - only a new install gets Brave Origin here.
PDF_STATE=~/.local/state/ohmydebn-config/pdf-20251107
if [ ! -f $PDF_STATE ] && [ -n "$BROWSER_BIN" ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring $BROWSER_NAME as default pdf viewer"
  xdg-mime default "$BROWSER_DESKTOP" application/pdf
  mkdir -p ~/.local/state/ohmydebn-config
  touch $PDF_STATE
fi
