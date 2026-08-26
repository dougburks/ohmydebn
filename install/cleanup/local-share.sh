#!/bin/bash

for DIR in ohmydebn cinnamon/extensions/gTile@OhMyDebn; do
  FULL_DIR=~/.local/share/$DIR
  if [ -d $FULL_DIR ]; then
    echo "Removing old directory $FULL_DIR"
    rm -rf $FULL_DIR
  fi
done

# A per-user desktop file with either of these names shadows (or, absent
# an explicit mimeapps.list default, is preferred over) the system-wide
# /usr/share/applications/li.oever.aether.url-handler.desktop this package
# installs - XDG searches ~/.local/share/applications before any system
# dir, for exactly this kind of per-user override. Both names are from
# before ohmydebn-aether-url-guard existed: aether-protocol-handler.desktop
# was aether's own upstream name, and li.oever.aether.url-handler.desktop
# is the current name but could exist here too from an older, pre-guard
# packaging that installed it per-user instead of system-wide. Either one
# left behind would silently keep aether:// links routing straight to
# aether with no confirmation prompt, defeating the guard entirely.
for FILE in aether-protocol-handler.desktop li.oever.aether.url-handler.desktop; do
  FULL_FILE=~/.local/share/applications/$FILE
  if [ -f $FULL_FILE ]; then
    echo "Removing old desktop file $FULL_FILE (shadows the guarded system one)"
    rm -f $FULL_FILE
  fi
done
