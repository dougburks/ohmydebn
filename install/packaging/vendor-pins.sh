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

# The other way round: a pin left behind after its app (and with it the
# repo) was removed with Remove > Package or apt directly - see
# ohmydebn-apt-pins.
/usr/share/ohmydebn/bin/ohmydebn-apt-pins --prune || true
