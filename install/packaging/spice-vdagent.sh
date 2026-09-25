#!/bin/bash

SPICE_VDAGENT_STATE=~/.local/state/ohmydebn-config/spice-vdagent-20260803
# Overridable for testing (see tests/unit/test-spice-vdagent.sh) the same
# way ohmydebn-update-check-install's OHMYDEBN_TEST_INTERVAL is - a real
# /dev path can't be faked into existing/not existing from a test without
# root, so the path itself has to be swappable instead.
SPICE_CHANNEL="${OHMYDEBN_TEST_SPICE_CHANNEL:-/dev/virtio-ports/com.redhat.spice.0}"
SYSTEMD_DIR="${OHMYDEBN_TEST_SYSTEMD_DIR:-/run/systemd/system}"
if [ ! -f $SPICE_VDAGENT_STATE ]; then

  # spice-vdagent is a guest-side agent that only does anything when the
  # VM's display is actually SPICE - dead weight otherwise (and the pin
  # below is intrusive to leave sitting in /etc/apt/preferences.d on a
  # machine that will never use the package). com.redhat.spice.0 is the
  # virtio-serial channel created specifically for the agent, present
  # only when a SPICE display + agent channel is configured (the
  # libvirt/virt-manager default whenever SPICE is picked) - a more
  # direct signal than systemd-detect-virt (true for any KVM guest,
  # SPICE or not) or an lspci QXL check (absent on newer virtio-gpu +
  # SPICE setups). Only gates future installs - an existing machine that
  # already ran the unconditional version of this script keeps whatever
  # it already has; this doesn't retroactively uninstall or un-pin
  # anything.
  if [ -e "$SPICE_CHANNEL" ]; then

    /usr/share/ohmydebn/bin/ohmydebn-headline "Making sure that the correct version of spice-vdagent is installed"

    # Debian Forky includes a newer version of spice-vdagent.
    # This newer version has a regression where it won't resize the screen properly.
    # We need to force a downgrade to the working version.
    sudo /usr/bin/apt -y install spice-vdagent=0.22.1-4.1 --allow-downgrades

    # Next we need to pin the version so that it can't be updated later
    sudo mkdir -p /etc/apt/preferences.d/
    sudo tee /etc/apt/preferences.d/ohmydebn-spice-vdagent >/dev/null <<'EOF'
Package: spice-vdagent
Pin: version 0.22.1-4.1
Pin-Priority: 1001
EOF

    # Set permissions on the file
    sudo chmod 644 /etc/apt/preferences.d/ohmydebn-spice-vdagent

    # The package starts its daemon from a udev rule on the SPICE port's
    # "add" event (70-spice-vdagentd.rules wants spice-vdagentd.socket),
    # which only fires at boot. Installed or downgraded here, after boot -
    # always the case on a distro whose own installer didn't include it,
    # like Pop!_OS - nothing started the daemon until the next reboot, so
    # the session agent gave up after 60 seconds and the display stopped
    # resizing with the VM window. Start the socket the way the rule would.
    # Only on systemd: without it, the package's init script runs the
    # daemon instead.
    if [ -d "$SYSTEMD_DIR" ]; then
      sudo systemctl start spice-vdagentd.socket || true
    fi

  fi

  # Finally, touch the state file so that we don't run this code on every update.
  mkdir -p ~/.local/state/ohmydebn-config
  touch $SPICE_VDAGENT_STATE
fi
