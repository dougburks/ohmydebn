#!/bin/bash

# Brave Origin is the default web browser for new installs. Only new ones:
# an install that already exists keeps the browser it was set up with
# (Chromium, for installs before this switch) - nothing here runs once the
# install-complete marker is present, and install/config/mimetypes.sh only
# picks a default browser on a first install too.
#
# Runs after power-user.sh: a --power-user install already installs Brave
# Origin itself, and its remove-all-optional pass would otherwise purge a
# copy installed here first only to reinstall it a moment later. The
# install script handles a distro that ships Brave Origin already (LCOS):
# no duplicate apt source, just the profile seed for a user who never ran
# it.
#
# Falling back to Chromium keeps a browser on the system when Brave Origin
# can't be installed (its repository unreachable, an architecture it
# doesn't build for) - the base ISO's Firefox may already be gone by now
# under --power-user. Brave's apt source is taken back out first if the
# install script added it, so a repository that just failed doesn't keep
# failing every apt update from here on.
if [ ! -f ~/.local/state/ohmydebn ]; then
  if ! /usr/share/ohmydebn/bin/ohmydebn-brave-origin-install --skip-prompt; then
    if /usr/share/ohmydebn/bin/ohmydebn-brave-repo is-ours; then
      /usr/share/ohmydebn/bin/ohmydebn-brave-repo remove || true
    fi
    echo "Warning: could not install Brave Origin - installing Chromium as the browser instead." >&2
    /usr/share/ohmydebn/bin/ohmydebn-chromium-install --skip-prompt ||
      echo "Warning: ohmydebn-chromium-install failed, continuing without a browser from OhMyDebn." >&2
  fi
fi
