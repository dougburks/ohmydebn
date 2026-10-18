#!/bin/bash

# Before 4.12.0, ohmydebn-powershell-install set up Microsoft's repository
# by installing Microsoft's packages-microsoft-prod.deb, unchecked (see
# ohmydebn-powershell-repo for why that changed). This moves existing
# installs to the checked setup. Keyed on the machine's state rather than
# a marker: PowerShell installed by OhMyDebn (its pin is there) with the
# setup package still installed. Once replaced, the package is gone, so it
# reruns harmlessly. A setup package installed without PowerShell isn't
# OhMyDebn's and stays. If the key can't be fetched or doesn't match,
# nothing has been changed yet, and the next update tries again.
APT_DIR="${OHMYDEBN_TEST_APT_DIR:-/etc/apt}"
if [ -f "$APT_DIR/preferences.d/powershell.pref" ] &&
  dpkg -s powershell >/dev/null 2>&1 && dpkg -s packages-microsoft-prod >/dev/null 2>&1; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Moving PowerShell to a checked Microsoft repository setup"
  if ! /usr/share/ohmydebn/bin/ohmydebn-powershell-repo ensure; then
    echo "PowerShell's repository setup wasn't changed. The next update will try again."
  fi
fi
