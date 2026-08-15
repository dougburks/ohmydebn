#!/bin/bash

set -euo pipefail

/usr/share/ohmydebn/bin/ohmydebn-headline "Installing any available package updates"
/usr/share/ohmydebn/bin/ohmydebn-update-system-pkgs
/usr/share/ohmydebn/bin/ohmydebn-opencode-migrate

/usr/share/ohmydebn/bin/ohmydebn-headline "Checking status of update notifications"
/usr/share/ohmydebn/bin/ohmydebn-update-check-install
