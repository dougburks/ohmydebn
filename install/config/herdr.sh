#!/bin/bash

# herdr is updated through apt, so its own update check is turned off once
# (see ohmydebn-herdr-config). Without herdr this does nothing;
# ohmydebn-herdr-install runs it when herdr is installed later.
/usr/share/ohmydebn/bin/ohmydebn-herdr-config || true
