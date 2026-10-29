#!/bin/bash

# Crush follows the OhMyDebn theme through its own theme file (see
# ohmydebn-theme-set-crush), which ohmydebn-crush-install selects. Installs
# that had Crush before that get the theme file and, once, the selection
# here; without Crush the hook does nothing.
/usr/share/ohmydebn/bin/ohmydebn-theme-set-crush --activate || true
