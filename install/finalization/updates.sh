#!/bin/bash

set -euo pipefail

/usr/share/ohmydebn/bin/ohmydebn-headline "tte rain" "Installing any available package updates"
/usr/share/ohmydebn/bin/ohmydebn-update-system-pkgs
/usr/share/ohmydebn/bin/ohmydebn-update-optional

/usr/share/ohmydebn/bin/ohmydebn-headline "tte rain" "Checking status of update notifications"
/usr/share/ohmydebn/bin/ohmydebn-update-check-install
