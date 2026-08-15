#!/bin/bash

# Blacklist kernel modules that have been the source of "in-place decrypt
# over externally-backed/shared pages" privilege-escalation bugs:
# algif_aead ("Copy Fail", CVE-2026-31431) and esp4/esp6/rxrpc ("Dirty
# Frag", CVE-2026-43284, CVE-2026-43500). Those specific CVEs are long
# patched in current kernels, but the same bug class has now surfaced
# independently across three separate subsystems within months of each
# other, so this stays in place as ongoing hardening against future bugs of
# the same shape rather than as a fix for any currently-open vulnerability.
# The functional cost is low for a desktop: few users need in-kernel AF_ALG
# crypto offload, IPsec ESP tunnels, or RxRPC/AFS.

NEEDS_INITRAMFS_UPDATE=false

DISABLE_ALGIF=/etc/modprobe.d/disable-algif-aead.conf
if [ ! -f $DISABLE_ALGIF ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Hardening against algif_aead in-place-decrypt bugs (e.g. Copy Fail)"
  echo "install algif_aead /bin/false" | sudo tee $DISABLE_ALGIF
  sudo rmmod algif_aead 2>/dev/null || true
  NEEDS_INITRAMFS_UPDATE=true
fi

DISABLE_DIRTYFRAG=/etc/modprobe.d/disable-esp4-esp6-rxrpc.conf
if [ ! -f $DISABLE_DIRTYFRAG ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Hardening against esp4/esp6/rxrpc in-place-decrypt bugs (e.g. Dirty Frag)"
  echo "install esp4 /bin/false" | sudo tee $DISABLE_DIRTYFRAG
  echo "install esp6 /bin/false" | sudo tee -a $DISABLE_DIRTYFRAG
  echo "install rxrpc /bin/false" | sudo tee -a $DISABLE_DIRTYFRAG
  # The exploit leaves contaminated data cached, so drop_caches is part of
  # the recommended mitigation sequence alongside blacklisting and rmmod.
  echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
  sudo rmmod esp4 esp6 rxrpc 2>/dev/null || true
  NEEDS_INITRAMFS_UPDATE=true
fi

# Only run once, even if both blocks above fired - it takes several seconds.
if [ "$NEEDS_INITRAMFS_UPDATE" = true ]; then
  sudo update-initramfs -u
fi
