#!/bin/bash

DISABLE_ALGIF=/etc/modprobe.d/disable-algif-aead.conf
if [ ! -f $DISABLE_ALGIF ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Disabling algif_aead kernel module to mitigate Copy Fail exploit"
  echo "install algif_aead /bin/false" | sudo tee $DISABLE_ALGIF
  sudo rmmod algif_aead 2>/dev/null || true
  sudo update-initramfs -u
fi
