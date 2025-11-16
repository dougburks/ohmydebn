#!/bin/bash

# Users that installed before we moved to a package repo need to add the repo, key, and packages

if [ ! -f /etc/apt/sources.list.d/ohmydebn.sources ]; then
  echo "Adding OhMyDebn repo"
  sudo tee /etc/apt/sources.list.d/ohmydebn.sources <<EOF
Types: deb
URIs: https://dougburks.github.io/ohmydebn-packages-testing/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/ohmydebn-keyring.gpg
EOF
fi

if [ ! -f /usr/share/keyrings/ohmydebn-keyring.gpg ]; then
  echo "Adding OhMyDebn repo key"
  curl -fsSL https://dougburks.github.io/ohmydebn-packages-testing/repo-key.asc |
    sudo gpg --dearmor -o /usr/share/keyrings/ohmydebn-keyring.gpg
fi

if ! dpkg -s "ohmydebn" >/dev/null 2>&1; then
  echo "Installing OhMyDebn packages from repo"
  sudo apt update
  sudo DEBIAN_FRONTEND=noninteractive apt install -y ohmydebn
fi
