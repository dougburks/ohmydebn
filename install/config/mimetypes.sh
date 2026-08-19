#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring chromium as default web browser"
  sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/chromium 200 || true
  sudo update-alternatives --set x-www-browser /usr/bin/chromium || true
  sudo update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/bin/chromium 200 || true
  sudo update-alternatives --set gnome-www-browser /usr/bin/chromium || true
  xdg-settings set default-web-browser chromium.desktop || true
  xdg-mime default chromium.desktop x-scheme-handler/http || true
  xdg-mime default chromium.desktop x-scheme-handler/https || true

  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring ristretto as default image viewer"
  xdg-mime default org.xfce.ristretto.desktop image/bmp image/gif image/jpeg image/png image/tiff image/webp
fi

PDF_STATE=~/.local/state/ohmydebn-config/pdf-20251107
if [ ! -f $PDF_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring chromium as default pdf viewer"
  xdg-mime default chromium.desktop application/pdf
  mkdir -p ~/.local/state/ohmydebn-config
  touch $PDF_STATE
fi
