#!/bin/bash

if [ ! -f ~/.local/state/ohmydebn ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "WARNING!

- OhMyDebn is intended for a clean new installation.
- OhMyDebn will remove apps like FireFox, Thunderbird, and others (unless you use the --no-uninstall option).
- OhMyDebn may make changes to your APT configuration.
- OhMyDebn is totally unsupported. If it breaks your system, you get to keep both pieces!

Press Enter to continue or Ctrl-c to cancel."
  read input
fi
