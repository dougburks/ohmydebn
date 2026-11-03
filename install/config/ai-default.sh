#!/bin/bash

# Antigravity stopped being an AI assistant OhMyDebn offers in 4.15.0:
# Google ended support for 1.x, the last version it released as a Debian
# package, and newer ones aren't packaged. A stored default of antigravity
# would make Super+A and the `a` alias fall back to OpenCode without a
# word, and the doctor flag it as invalid, so it's cleared here once, with
# a note. Keyed on the file's contents, so it needs no marker.
DEFAULT_AI_FILE=~/.config/ohmydebn/current/default-ai
if [ "$(cat "$DEFAULT_AI_FILE" 2>/dev/null)" = "antigravity" ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Resetting your default AI assistant"
  echo "Antigravity is no longer offered, so your default AI assistant is now OpenCode."
  echo "To choose another, open the OhMyDebn Menu and go to Setup > Defaults > Agent."
  rm -f "$DEFAULT_AI_FILE"
fi
