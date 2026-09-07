#!/bin/bash

# Ubuntu has no "chromium" apt package (see CHROMIUM_PACKAGE in
# install/packaging/dependencies.sh) - it only ever gets chromium as a
# strictly-confined snap, which has no /usr/bin/chromium at all. The real
# binary is /snap/bin/chromium (itself a symlink into snapd's own command
# dispatcher, not a broken link), and its desktop file is registered under
# snapd's own naming scheme rather than plain "chromium.desktop". Confirmed
# working end-to-end - update-alternatives, xdg-settings, xdg-mime, and an
# actual xdg-open launch - on Ubuntu 24.04/26.04 with Cinnamon.
if dpkg -s chromium >/dev/null 2>&1; then
  CHROMIUM_BIN=/usr/bin/chromium
  CHROMIUM_DESKTOP=chromium.desktop
elif snap list chromium >/dev/null 2>&1; then
  CHROMIUM_BIN=/snap/bin/chromium
  CHROMIUM_DESKTOP=chromium_chromium.desktop
fi

if [ ! -f ~/.local/state/ohmydebn ]; then
  if [ -n "$CHROMIUM_BIN" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring chromium as default web browser"
    sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser "$CHROMIUM_BIN" 200 || true
    sudo update-alternatives --set x-www-browser "$CHROMIUM_BIN" || true
    sudo update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser "$CHROMIUM_BIN" 200 || true
    sudo update-alternatives --set gnome-www-browser "$CHROMIUM_BIN" || true
    xdg-settings set default-web-browser "$CHROMIUM_DESKTOP" || true
    xdg-mime default "$CHROMIUM_DESKTOP" x-scheme-handler/http || true
    xdg-mime default "$CHROMIUM_DESKTOP" x-scheme-handler/https || true
  fi

  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring ristretto as default image viewer"
  xdg-mime default org.xfce.ristretto.desktop image/bmp image/gif image/jpeg image/png image/tiff image/webp
fi

PDF_STATE=~/.local/state/ohmydebn-config/pdf-20251107
if [ ! -f $PDF_STATE ] && [ -n "$CHROMIUM_BIN" ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring chromium as default pdf viewer"
  xdg-mime default "$CHROMIUM_DESKTOP" application/pdf
  mkdir -p ~/.local/state/ohmydebn-config
  touch $PDF_STATE
fi
