#!/bin/bash

if [ "${OHMYDEBN_SKIP_UPGRADE:-}" = "1" ]; then
  # install.sh --skip-upgrade - see its comment - or ohmydebn-reset-config
  # (OHMYDEBN_RESET), which never upgrades, so there's nothing to announce:
  # naming an option the user never typed only confused. Only the full
  # upgrade is skipped; everything else in this stage still runs.
  if [ "${OHMYDEBN_RESET:-}" != "1" ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Skipping the full system update (--skip-upgrade)"
    echo "Run ohmydebn-update when convenient to bring the base OS packages up to date."
  fi
else
  /usr/share/ohmydebn/bin/ohmydebn-headline "Installing any available package updates"
  /usr/share/ohmydebn/bin/ohmydebn-update-system-pkgs
fi
/usr/share/ohmydebn/bin/ohmydebn-opencode-migrate

/usr/share/ohmydebn/bin/ohmydebn-headline "Checking status of update notifications"
/usr/share/ohmydebn/bin/ohmydebn-update-check-install
