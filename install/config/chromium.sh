#!/bin/bash

# config/chromium/External Extensions/*.json below uses Chromium's
# ExternalPrefLoader mechanism: any JSON file dropped in that directory gets
# silently installed on next launch, no Chrome Web Store visit or consent
# dialog required. The extension ID in that filename can't be sanity-checked
# by eye, so any future PR changing it needs to be verified against the
# store, not just diffed: ddkjiahejlhfcafbddmgiahcphecmpfh is uBlock Origin
# Lite by Raymond Hill (gorhill) -
# https://chromewebstore.google.com/detail/ddkjiahejlhfcafbddmgiahcphecmpfh
# (bundling it is documented at https://ohmydebn.org). Its
# external_update_url points at Google's own CRX update service, so the
# code itself is still fetched and signature-verified through the same
# channel a manual Web Store install would use - this only skips the
# install prompt, it doesn't skip Google's signing check. It's also still
# user-removable from chrome://extensions, unlike a policy forcelist.

# Ubuntu has no "chromium" apt package (see CHROMIUM_PACKAGE in
# install/packaging/dependencies.sh) - it only ever gets chromium as a
# strictly-confined snap, installed via the "chromium-browser" transitional
# deb's postinst. A snap's confinement remaps $HOME inside its sandbox, so
# Chromium's ExternalPrefLoader never sees ~/.config/chromium there; the
# profile it actually reads lives under ~/snap/chromium/common/chromium
# instead. Pre-creating that path before the snap's own first run works
# because both Chromium's profile bootstrap and snapd's per-user directory
# setup are additive - each fills in whatever's missing around existing
# content rather than overwriting it. Verified manually on Ubuntu 24.04/26.04.
if dpkg -s "chromium" >/dev/null 2>&1; then
  CHROMIUM_PARENT=~/.config
elif snap list chromium >/dev/null 2>&1; then
  CHROMIUM_PARENT=~/snap/chromium/common
else
  return 0
fi

if [ ! -d "$CHROMIUM_PARENT/chromium" ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring chromium"
  mkdir -p "$CHROMIUM_PARENT"
  cp -av /usr/share/ohmydebn/config/chromium "$CHROMIUM_PARENT/"
  echo
fi
