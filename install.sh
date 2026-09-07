#!/bin/bash

set -e

# Parse command line arguments
POWER_USER=false
ASSUME_YES=false
for arg in "$@"; do
  case $arg in
  --power-user)
    POWER_USER=true
    shift
    ;;
  --yes)
    # Skips every "Press Enter to continue" prompt below, for unattended runs
    # (CI smoke tests, scripted provisioning). Everything these prompts warn
    # about still happens - this only removes the pause to read it.
    ASSUME_YES=true
    shift
    ;;
  *)
    # Unknown option
    ;;
  esac
done

# Check what Linux distro we're running on
DISTRO_OK=false
OS_RELEASE="${OHMYDEBN_TEST_OS_RELEASE:-/etc/os-release}"
if [ -f "$OS_RELEASE" ]; then
  # shellcheck disable=SC1090
  . "$OS_RELEASE"
  case "$ID" in
  debian)
    [ "$VERSION_CODENAME" = "trixie" ] && DISTRO_OK=true
    ;;
  linuxmint)
    # LMDE (Debian-based) sets DEBIAN_CODENAME; regular Mint (Ubuntu-based)
    # sets UBUNTU_CODENAME instead - both report ID=linuxmint, so both need
    # checking here. Regular Mint 22.x tracks Ubuntu 24.04 "noble" as its
    # base (VERSION_CODENAME is Mint's own release name, e.g. "zena" - not
    # useful for distro-family detection).
    if [ "$DEBIAN_CODENAME" = "trixie" ] || [ "$UBUNTU_CODENAME" = "noble" ]; then
      DISTRO_OK=true
    fi
    ;;
  kali)
    [ "$VERSION_CODENAME" = "kali-rolling" ] && DISTRO_OK=true
    ;;
  ubuntu)
    case "$VERSION_CODENAME" in
    noble | resolute) DISTRO_OK=true ;;
    esac
    ;;
  esac
fi

if [ "$DISTRO_OK" = false ] && [ "$ASSUME_YES" = false ]; then
  clear
  cat <<EOF
WARNING!

OhMyDebn is designed for Debian 13, Linux Mint 22.3, Linux Mint Debian Edition 7, Kali Linux (Rolling), and Ubuntu 24.04/26.04.

Trying to install OhMyDebn on anything else is untested and unsupported.

IF IT BREAKS YOUR SYSTEM, YOU GET TO KEEP BOTH PIECES!

Press Enter if you are sure you want to continue or Ctrl-c to cancel.
EOF
  read -r _
fi

# Check what user is running the script
if [ "$UID" -eq 0 ] && [ "$ASSUME_YES" = false ]; then
  clear
  cat <<EOF
Looks like you're running as root.

Instead of running as root, you most likely want to
run this as a normal user that has sudo privileges.

Press Enter if you are sure you want to continue as root
or Ctrl-c to cancel.
EOF
  read -r _
fi

# Only show welcome message on new installations
if [ ! -f ~/.local/state/ohmydebn ]; then
  # Unlike the two clear calls above, this one isn't skipped outright under
  # --yes (the message and the setup below it still run) - but clear itself
  # still needs to be, since it fails outright with no TERM/TTY (a headless
  # CI/container run, under --yes) and set -e would take the whole install
  # down over a cosmetic screen-clear no one is there to see.
  if [ "$ASSUME_YES" = false ]; then
    clear
  fi
  cat <<EOF
Welcome to OhMyDebn!

OhMyDebn is a debonair Linux desktop for power users. It gives you the stability of the Debian or Ubuntu distros, the ease of use of the Cinnamon desktop, and the power of AI, containers, and virtualization.

Debonair strides bold,
Elegance in every step,
Stars bow to its charm.
 -- AI, probably

WARNING!

- OhMyDebn is intended for a clean new installation.
- OhMyDebn will make changes to your APT configuration.
- If it breaks your system, you get to keep both pieces!

Press Enter to continue or Ctrl-c to cancel.
EOF
  if [ "$ASSUME_YES" = false ]; then
    read -r _
  fi

  # Update time
  sudo /usr/bin/chronyc makestep >/dev/null 2>&1 || true

  # Check to see if we have an APT configuration
  DEBIANSOURCES=/etc/apt/sources.list.d/debian.sources
  PROXMOXSOURCES=/etc/apt/sources.list.d/proxmox.sources
  MINTSOURCES=/etc/apt/sources.list.d/official-package-repositories.list
  if [ -f $DEBIANSOURCES ] ||
    [ -f $PROXMOXSOURCES ] ||
    [ -f $MINTSOURCES ] ||
    [ "$ID" = "kali" ] ||
    [ "$ID" = "ubuntu" ]; then
    echo "Found an APT sources file in /etc/apt/sources.list.d/"
  else
    # Some Debian installation methods have a broken APT configuration so try to work around that
    SOURCESLIST=/etc/apt/sources.list
    if ! grep -q "debian.org" $SOURCESLIST >/dev/null 2>&1; then
      echo "$SOURCESLIST does not have any debian.org references."
      if [ -f $SOURCESLIST ]; then
        echo "Renaming $SOURCESLIST to $SOURCESLIST.orig"
        sudo mv $SOURCESLIST $SOURCESLIST.orig
      fi
      # Reaching this point already guarantees $DEBIANSOURCES and
      # $MINTSOURCES don't exist (the outer if above checks both, plus
      # $PROXMOXSOURCES and Kali, before ever entering this else branch),
      # so no need to re-check either here.
      echo "Creating $DEBIANSOURCES and adding the following:"
      cat <<EOF | sudo tee -a $DEBIANSOURCES
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    fi
  fi

  sudo /usr/bin/apt update && sudo /usr/bin/apt install -y curl gpg

fi

if [ ! -f /etc/apt/sources.list.d/ohmydebn.sources ]; then
  sudo tee /etc/apt/sources.list.d/ohmydebn.sources <<EOF
Types: deb
URIs: https://packages.ohmydebn.org/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/ohmydebn-keyring.gpg
EOF
fi

if [ ! -f /usr/share/keyrings/ohmydebn-keyring.gpg ]; then
  curl -fsSL https://packages.ohmydebn.org/repo-key.asc |
    sudo gpg --dearmor -o /usr/share/keyrings/ohmydebn-keyring.gpg
fi

if ! dpkg -s "ohmydebn" >/dev/null 2>&1; then
  sudo /usr/bin/apt update
  sudo /usr/bin/apt install -y ohmydebn
fi

# Exported so install/packaging/power-user.sh (sourced later, from
# ohmydebn.sh below) can see it - the --power-user removal step has to run
# after install/packaging/dependencies.sh installs its packages, not here,
# since cinnamon-desktop-environment hard-depends on
# "gnome-calculator | galculator" and purging gnome-calculator before
# galculator exists would briefly leave that dependency unsatisfied.
export POWER_USER

export PATH="/usr/share/ohmydebn/bin:$PATH"

# ohmydebn.sh applies the desktop-config layer (gsettings, systemctl, Cinnamon
# theming) on top of the apt package layer above - it needs a running session
# bus, X/Cinnamon, and a real init system, none of which exist in a headless
# container. OHMYDEBN_TEST_SKIP_CONFIG lets a smoke test stop right after the
# package layer succeeds - the part that actually differs across Debian/Kali/
# Mint - without the config layer's inevitable failure there masking a
# genuine package-layer result.
if [ -n "${OHMYDEBN_TEST_SKIP_CONFIG:-}" ]; then
  echo "OHMYDEBN_TEST_SKIP_CONFIG set - skipping desktop-config layer (ohmydebn.sh)"
  exit 0
fi

source /usr/share/ohmydebn/ohmydebn.sh "$@"
