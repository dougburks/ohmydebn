#!/bin/bash

# Pins a vendor-added apt repo that an older OhMyDebn left unpinned. Before
# 4.11.0, ohmydebn-chatgpt-install didn't pin the repo ChatGPT's own
# package adds (chatgpt.sources), so OpenAI's key was trusted to sign any
# package name on machines that installed ChatGPT. The installer pins it
# now; this gives existing installs the same pin, and keeps the doctor's
# pin check from failing for them. Keyed on the files themselves (repo
# present, pin missing), so it reruns harmlessly and needs no marker -
# and does nothing on machines without ChatGPT. The pin text matches
# ohmydebn-chatgpt-install's; keep them identical.
APT_DIR="${OHMYDEBN_TEST_APT_DIR:-/etc/apt}"
if [ -e "$APT_DIR/sources.list.d/chatgpt.sources" ] && [ ! -f "$APT_DIR/preferences.d/chatgpt.pref" ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Restricting ChatGPT's apt repository to ChatGPT"
  sudo mkdir -p "$APT_DIR/preferences.d"
  printf 'Package: *\nPin: origin "persistent.oaistatic.com"\nPin-Priority: -1\n\nPackage: chatgpt\nPin: origin "persistent.oaistatic.com"\nPin-Priority: 500\n' |
    sudo tee "$APT_DIR/preferences.d/chatgpt.pref" >/dev/null
fi

# The same for Brave: before 4.5.0, OhMyDebn wrote Brave's sources file
# (brave-browser-release.sources) with no pin, and ohmydebn-brave-repo
# leaves an existing repo as it finds it, so installs from then never got
# one. Only OhMyDebn's own .sources file: a distro's own source for Brave
# (LCOS's brave.list, Zorin OS's brave-browser-release.list) is the
# distro's to manage. The pin text matches ohmydebn-brave-repo's; keep
# them identical.
if [ -e "$APT_DIR/sources.list.d/brave-browser-release.sources" ] && [ ! -f "$APT_DIR/preferences.d/brave-browser-release.pref" ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Restricting Brave's apt repository to Brave"
  sudo mkdir -p "$APT_DIR/preferences.d"
  printf 'Package: *\nPin: origin "%s"\nPin-Priority: -1\n\nPackage: brave-browser brave-origin brave-keyring\nPin: origin "%s"\nPin-Priority: 500\n' "brave-browser-apt-release.s3.brave.com" "brave-browser-apt-release.s3.brave.com" |
    sudo tee "$APT_DIR/preferences.d/brave-browser-release.pref" >/dev/null
fi

# The other way round: a pin left behind after its app (and with it the
# repo) was removed with Remove > Package or apt directly - see
# ohmydebn-apt-pins.
/usr/share/ohmydebn/bin/ohmydebn-apt-pins --prune || true
