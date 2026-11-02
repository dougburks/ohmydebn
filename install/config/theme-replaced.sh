#!/bin/bash

# Omarchy 4.5 replaced its Osaka Jade theme with Jade Horse, a jade palette
# of its own, so ohmydebn-themes-omarchy no longer ships Osaka Jade. A user
# who had it active keeps their copy of it in ~/.config/ohmydebn/current,
# so the desktop looks the same, but the theme is gone from the pickers,
# the doctor fails "theme directory exists", and reapplying it (a config
# reset, Aether) says it doesn't exist. So they're moved to Jade Horse
# once, with a note. Keyed on the theme name and the shipped themes, so it
# needs no marker: it does nothing once the theme has changed, for an
# Osaka Jade of the user's own in ~/.config/ohmydebn/themes, or before the
# package that ships Jade Horse is installed. --no-intro: a full-screen
# intro would cover this update's terminal.
THEME_NAME_FILE=~/.config/ohmydebn/current/theme.name
SHIPPED_THEMES=/usr/share/ohmydebn-themes
if [ "$(cat "$THEME_NAME_FILE" 2>/dev/null)" = "osaka-jade" ] &&
  [ ! -d ~/.config/ohmydebn/themes/osaka-jade ] &&
  [ ! -d "$SHIPPED_THEMES/osaka-jade" ] && [ -d "$SHIPPED_THEMES/jade-horse" ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Switching from Osaka Jade to Jade Horse"
  echo "Omarchy replaced its Osaka Jade theme with Jade Horse, so your theme is now Jade Horse."
  echo "To choose another, open the OhMyDebn Menu and go to Appearance > Theme."
  /usr/share/ohmydebn/bin/ohmydebn-theme-set --no-intro jade-horse ||
    echo "Couldn't switch to Jade Horse; choose a theme in the OhMyDebn Menu under Appearance > Theme."
fi
