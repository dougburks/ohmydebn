#!/bin/bash

set -euo pipefail

if [ "${OHMYDEBN_SKIP_UPGRADE:-}" = "1" ]; then
  # install.sh --skip-upgrade - see its comment. Only the full upgrade is
  # skipped; everything else in this stage still runs.
  /usr/share/ohmydebn/bin/ohmydebn-headline "Skipping the full system update (--skip-upgrade)"
  echo "Run ohmydebn-update when convenient to bring the base OS packages up to date."
else
  /usr/share/ohmydebn/bin/ohmydebn-headline "Installing any available package updates"
  /usr/share/ohmydebn/bin/ohmydebn-update-system-pkgs
fi
/usr/share/ohmydebn/bin/ohmydebn-opencode-migrate

/usr/share/ohmydebn/bin/ohmydebn-headline "Checking status of update notifications"
/usr/share/ohmydebn/bin/ohmydebn-update-check-install
