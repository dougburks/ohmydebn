#!/bin/bash

DISABLE_ALGIF=/etc/modprobe.d/disable-algif-aead.conf
if [ ! -f $DISABLE_ALGIF ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Disabling algif_aead kernel module to mitigate Copy Fail exploit"
  echo "install algif_aead /bin/false" | sudo tee $DISABLE_ALGIF
  sudo rmmod algif_aead 2>/dev/null || true
  sudo update-initramfs -u
fi

DISABLE_DIRTYFRAG=/etc/modprobe.d/disable-esp4-esp6-rxrpc.conf
if [ ! -f $DISABLE_DIRTYFRAG ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Disabling multiple kernel modules to mitigate Dirty Frag exploit"
  echo "install esp4 /bin/false" | sudo tee $DISABLE_DIRTYFRAG
  echo "install esp6 /bin/false" | sudo tee -a $DISABLE_DIRTYFRAG
  echo "install rxrpc /bin/false" | sudo tee -a $DISABLE_DIRTYFRAG
  echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
  sudo rmmod esp4 esp6 rxrpc 2>/dev/null || true
  sudo update-initramfs -u
fi
