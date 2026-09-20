#!/bin/bash

# Brave Origin is the default browser for new installs (install/packaging/
# browser.sh); Chromium is what installs before that switch got, and what
# browser.sh falls back to when Brave Origin can't be installed. Whichever
# is present is the one to configure, Brave Origin first. The configuring
# itself - alternatives, xdg-settings, scheme handlers, PDF viewer - is
# bin/ohmydebn-browser-set-default's, shared with the browser installers'
# "make it your default?" question and the menu's Browsers > Set Default,
# so a new install and a later switch set the same things the same way.
#
# Ubuntu has no "chromium" apt package (see bin/ohmydebn-chromium-install) -
# it only ever gets chromium as a strictly-confined snap. The package name
# handed on is still "chromium"; ohmydebn-browser-set-default resolves the
# snap's own binary and desktop id itself.
BROWSER_PKG=""
if dpkg -s brave-origin >/dev/null 2>&1; then
  BROWSER_PKG=brave-origin
elif dpkg -s chromium >/dev/null 2>&1 || snap list chromium >/dev/null 2>&1; then
  BROWSER_PKG=chromium
fi

NEW_INSTALL=false
[ -f ~/.local/state/ohmydebn ] || NEW_INSTALL=true

if [ "$NEW_INSTALL" = true ]; then
  if [ -n "$BROWSER_PKG" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-browser-set-default "$BROWSER_PKG" || true
  fi

  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring ristretto as default image viewer"
  xdg-mime default org.xfce.ristretto.desktop image/bmp image/gif image/jpeg image/png image/tiff image/webp
fi

# Existing installs already carry this marker, so their PDF handler stays
# whatever it is (chromium) - only a new install gets Brave Origin here. A
# new install just got its PDF viewer along with the browser above; an
# existing install from before the PDF handler was set at all gets only
# that, its default browser left alone.
PDF_STATE=~/.local/state/ohmydebn-config/pdf-20251107
if [ ! -f $PDF_STATE ] && [ -n "$BROWSER_PKG" ]; then
  if [ "$NEW_INSTALL" = false ]; then
    /usr/share/ohmydebn/bin/ohmydebn-browser-set-default --pdf-only "$BROWSER_PKG" || true
  fi
  mkdir -p ~/.local/state/ohmydebn-config
  touch $PDF_STATE
fi
