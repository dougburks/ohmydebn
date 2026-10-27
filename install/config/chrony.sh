#!/bin/bash

# chrony keeps the clock right (a dependency in dependencies.sh): a clock
# that drifts makes TLS certificates and apt's Release files "not valid
# yet", which looks like a broken update. Most distros start it as it's
# installed, but Kali's policy leaves anything that starts after the
# network disabled at install time (its update-rc.d wrapper), chrony
# included, so nothing kept the clock in sync there. chrony as Debian
# configures it only syncs this machine's clock; it serves time to no one.
#
# Once per machine, like the firewall (ufw.sh): someone who later turns
# chrony off on purpose keeps it off. The marker is written only once
# chrony is installed, so a run where it wasn't yet tries again next time.
# OHMYDEBN_TEST_SYSTEMD_DIR as in spice-vdagent.sh.
CHRONY_SYSTEM_STATE_DIR=/var/lib/ohmydebn
CHRONY_SYSTEM_STATE=$CHRONY_SYSTEM_STATE_DIR/chrony-enabled
CHRONY_SYSTEMD_DIR="${OHMYDEBN_TEST_SYSTEMD_DIR:-/run/systemd/system}"
if [ ! -f $CHRONY_SYSTEM_STATE ] && dpkg -s chrony >/dev/null 2>&1; then
  if [ -d "$CHRONY_SYSTEMD_DIR" ]; then
    # Running now isn't enough: disabled, it wouldn't start after a reboot.
    if ! systemctl is-enabled --quiet chrony 2>/dev/null || ! pgrep -x chronyd >/dev/null 2>&1; then
      /usr/share/ohmydebn/bin/ohmydebn-headline "Turning on clock synchronization (chrony)"
      sudo systemctl enable --now chrony || true
    fi
  elif ! pgrep -x chronyd >/dev/null 2>&1; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Turning on clock synchronization (chrony)"
    sudo update-rc.d chrony enable || true
    sudo service chrony start || true
  fi
  sudo mkdir -p $CHRONY_SYSTEM_STATE_DIR
  sudo touch $CHRONY_SYSTEM_STATE
fi
