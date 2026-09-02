#!/bin/bash
#
# dependencies.sh: Install packages that aren't guaranteed to exist on every
# Debian 13 flavor / Kali / Debian testing target, so ohmydebn's own .deb
# only hard-depends on packages it can guarantee (its own repo packages,
# plus a handful of universal framework plumbing - see
# build-package-ohmydebn.sh in the ohmydebn-package-build repo). Everything
# here installs in a single batched call so dpkg's trigger-processing cost
# (mandb, icon caches, desktop/mime databases) is paid once instead of once
# per package.
#

# Ubuntu carries no "chromium" apt package at all (unlike Debian/Kali/Mint) -
# it only ships "chromium-browser", a transitional package whose postinst
# installs the real thing as a strictly-confined snap. install/config/
# chromium.sh accounts for the snap's different profile layout when seeding
# the bundled extension.
CHROMIUM_PACKAGE="chromium"
[ "$ID" = "ubuntu" ] && CHROMIUM_PACKAGE="chromium-browser"

PACKAGES=(
  # Per-app packages, one each, matching install/config/<app>.sh
  # (fastfetch is the exception - its theming lives entirely in
  # config/fastfetch/*.tpl + ohmydebn-theme-set-fastfetch, no
  # install/config/fastfetch.sh needed)
  alacritty
  bat
  btop
  cava
  "$CHROMIUM_PACKAGE"
  fastfetch
  gedit
  keepassxc
  neovim

  # Cinnamon desktop + theming
  cinnamon-desktop-environment
  yaru-theme-gtk
  yaru-theme-icon
  libspa-0.2-bluetooth
  gvfs-backends
  libnotify-bin

  # Dev toolchain
  gcc
  pkg-config
  libglib2.0-bin
  libgtk-4-dev
  libadwaita-1-dev
  python-is-python3
  pipx

  # Media tools
  ffmpeg
  imagemagick
  gcolor3
  ristretto
  xournalpp
  galculator

  # CLI tools
  htop
  ripgrep
  fzf
  eza
  duf
  zoxide
  lazygit
  zip
  yq
  jq
  vim
  wget
  binutils
  gum
  grc

  # Network & security
  ufw
  gufw
  chrony

  # Shell
  zsh
  zsh-autosuggestions
  zsh-syntax-highlighting
  starship
)

/usr/share/ohmydebn/bin/ohmydebn-pkg-install-optional "${PACKAGES[@]}"
