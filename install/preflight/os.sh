#!/bin/bash

if ! grep -q "13 (trixie)" /etc/os-release; then
  echo "OhMyDebn is designed for Debian 13 Cinnamon. Exiting!"
  exit 1
fi
