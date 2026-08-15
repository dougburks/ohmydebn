#!/bin/bash

# When install.sh was run with --power-user (see the exported $POWER_USER),
# remove the optional apps that ship on the base Debian 13 Cinnamon ISO
# (Firefox, LibreOffice, etc.) and install a curated set of power-user
# extras. This has to run after dependencies.sh above, not before it:
# cinnamon-desktop-environment hard-depends on
# "gnome-calculator | galculator", and purging gnome-calculator before
# dependencies.sh has installed galculator would briefly leave that
# dependency unsatisfied. Still runs before finalization's one big
# `apt full-upgrade`, so removed packages never get needlessly upgraded
# first and the newly-installed extras get swept into that same upgrade
# pass instead of needing a separate one later. A failure in any one of
# these (e.g. a network hiccup) is non-fatal and shouldn't block the rest
# of the install.
if [ "${POWER_USER:-false}" = true ]; then
  /usr/share/ohmydebn/bin/ohmydebn-pkg-remove-all-optional --skip-prompt ||
    echo "Warning: ohmydebn-pkg-remove-all-optional failed, continuing." >&2

  for SCRIPT in ohmydebn-boxes-install ohmydebn-brave-origin-install ohmydebn-claude-code-install \
    ohmydebn-gimp-install ohmydebn-opencode-install ohmydebn-podman-install; do
    "/usr/share/ohmydebn/bin/$SCRIPT" --skip-prompt ||
      echo "Warning: $SCRIPT failed, continuing." >&2
  done

  # Preseed iperf3's debconf question (whether to start its server daemon
  # automatically) so its postinst doesn't pop up an interactive prompt below.
  echo "iperf3 iperf3/start_daemon boolean false" | sudo debconf-set-selections

  # keepassxc-minimal Conflicts with keepassxc-full (dependencies.sh's plain
  # `keepassxc` pulls in keepassxc-full by default); installing it here
  # makes apt swap the two automatically.
  /usr/share/ohmydebn/bin/ohmydebn-pkg-install-optional keepassxc-minimal rclone openssh-server pdftk-java rsync \
    ethtool traceroute lshw shellcheck iperf3 ||
    echo "Warning: failed to install keepassxc-minimal/rclone/openssh-server/pdftk-java/rsync/ethtool/traceroute/lshw/shellcheck/iperf3, continuing." >&2

  /usr/share/ohmydebn/bin/ohmydebn-magnifier-enable ||
    echo "Warning: ohmydebn-magnifier-enable failed, continuing." >&2
fi
