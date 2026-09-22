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

PACKAGES=(
  # Per-app packages, one each, matching install/config/<app>.sh
  # (fastfetch is the exception - its theming lives entirely in
  # config/fastfetch/*.tpl + ohmydebn-theme-set-fastfetch, no
  # install/config/fastfetch.sh needed)
  alacritty
  bat
  btop
  cava
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

  # ohmydebn-menu's Setup > Bluetooth/Printers targets. Only Recommends
  # of cinnamon-desktop-environment, and the batched install above runs
  # with --no-install-recommends (see ohmydebn-pkg-install-optional) - so
  # without naming them here, any install not seeded from the Debian
  # Cinnamon ISO never got them and both menu entries were silent
  # no-ops. Found in review. (Neither has a cinnamon-settings module to
  # fall back to - Debian's Cinnamon ships no cs_bluetooth/cs_printers.)
  blueman
  system-config-printer

  # VTE terminal-widget introspection data, for the terminal embedded in
  # ohmydebn-update-gui's window (python3-gi + GTK3's own gir both ride
  # in with cinnamon-desktop-environment already; this one doesn't).
  # ohmydebn-update-gui falls back to the old alacritty flow whenever
  # this isn't installed yet - i.e. exactly once, on the update that
  # first brings it in.
  gir1.2-vte-2.91

  # Wnck introspection data, for ohmydebn-menu-picker's window-switcher
  # mode (Ctrl+Alt+Tab) - it imports Wnck at startup, so without this the
  # picker fails outright and every menu, plus ohmydebn-update, dies with
  # "Namespace Wnck not available". Cinnamon itself only depends on the
  # libwnck-3-0 library, not this typelib; the Debian and Mint Cinnamon
  # images happen to carry it via orca (a Recommends of
  # cinnamon-desktop-environment), which is why it looked pre-installed
  # everywhere until a --no-install-recommends install on a non-Cinnamon
  # base (LCOS/Devuan XFCE) surfaced the gap.
  gir1.2-wnck-3.0

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

# The web browser isn't in this list: Brave Origin comes from Brave's own
# repository, which has to be configured (and refreshed) before it can be
# installed, so install/packaging/browser.sh handles it - on new installs
# only - after this batch.
/usr/share/ohmydebn/bin/ohmydebn-pkg-install-optional "${PACKAGES[@]}"
