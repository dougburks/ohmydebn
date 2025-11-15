#!/bin/bash

set -e
clear
cat <<EOF
Welcome to OhMyDebn!

OhMyDebn is a debonair Debian + Cinnamon setup inspired by Omarchy.

Debonair strides bold,
Elegance in every step,
Stars bow to its charm.
 -- AI, probably
EOF

if [ ! -f ~/.local/state/ohmydebn ]; then
  cat <<EOF

WARNING!

- OhMyDebn is intended for a clean new installation.
- OhMyDebn will remove apps like FireFox, Thunderbird, and others (unless you use the --no-uninstall option).
- OhMyDebn will make changes to your APT configuration.
- OhMyDebn is totally unsupported. If it breaks your system, you get to keep both pieces!

Press Enter to continue or Ctrl-c to cancel.
EOF
  read input
fi

# Check to see if we have an APT configuration
if [ -f /etc/apt/sources.list.d/debian.sources ] || [ -f /etc/apt/sources.list.d/proxmox.sources ]; then
  echo "Found an APT sources file in /etc/apt/sources.list.d/"
else
  # Some Debian installation methods have a broken APT configuration so try to work around that
  SOURCESLIST=/etc/apt/sources.list
  if ! grep -q "debian.org" $SOURCESLIST >/dev/null 2>&1; then
    echo "$SOURCESLIST does not have any debian.org references."
    if [ -f $SOURCESLIST ]; then
      echo "Renaming $SOURCESLIST to $SOURCESLIST.orig"
      sudo mv $SOURCESLIST $SOURCESLIST.orig
    fi
    DEBIANSOURCES=/etc/apt/sources.list.d/debian.sources
    if [ ! -f $DEBIANSOURCES ]; then
      echo "Creating $DEBIANSOURCES and adding the following:"
      cat <<EOF | sudo tee -a $DEBIANSOURCES
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    fi
  fi
fi

if [ ! -f /etc/apt/sources.list.d/ohmydebn.sources ]; then
  sudo tee /etc/apt/sources.list.d/ohmydebn.sources <<EOF
Types: deb
URIs: https://dougburks.github.io/ohmydebn-packages-testing/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/ohmydebn-keyring.gpg
EOF
fi

if [ ! -f /usr/share/keyrings/ohmydebn-keyring.gpg ]; then
  curl -fsSL https://dougburks.github.io/ohmydebn-packages-testing/repo-key.asc |
    sudo gpg --dearmor -o /usr/share/keyrings/ohmydebn-keyring.gpg
fi

if ! dpkg -s "ohmydebn" >/dev/null 2>&1; then
  sudo apt update
  sudo DEBIAN_FRONTEND=noninteractive apt install -y ohmydebn
fi

source /opt/ohmydebn/ohmydebn.sh "$@"
