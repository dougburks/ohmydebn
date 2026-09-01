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

if ! dpkg -s "chromium" >/dev/null 2>&1; then
  exit 0
fi

if [ ! -d ~/.config/chromium ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring chromium"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/chromium ~/.config/
  echo
fi
