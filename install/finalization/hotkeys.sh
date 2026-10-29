#!/bin/bash

# Nothing in this release sources this file: it's here for updates from
# OhMyDebn 4.5.0, 4.6.0 and 4.7.0. Their ohmydebn-update carried on when
# its first `apt update` failed (PackageKit holding apt's lock, say), so
# instead of upgrading this package and running the new install, it ran
# its own old install steps. Their last stage, finalization/updates.sh,
# upgrades every package, this one included; the old run had already read
# its finalization/all.sh, and the next file that sources is this one, by
# the name it had then (it's keybinding.sh now). Missing, it stopped the
# update there. Run this release's whole install from the start instead,
# then end the old run, rather than mixing old steps with new ones.
# tests/unit/test-old-update-handoff.sh checks every file those releases'
# finalization/all.sh sources is still here.
/usr/share/ohmydebn/bin/ohmydebn-headline "OhMyDebn was upgraded during this update - finishing it with the new version"
bash /usr/share/ohmydebn/install.sh
exit $?
