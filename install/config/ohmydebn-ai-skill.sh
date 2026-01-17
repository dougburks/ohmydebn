#!/bin/bash

SKILL_STATE=~/.local/state/ohmydebn-config/skill-20260116
if [ ! -f $SKILL_STATE ]; then

  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring AI skill"

  # Place in ~/.claude/skills since all tools populate from there as well as their own sources
  mkdir -p ~/.claude/skills
  ln -s /usr/share/ohmydebn/config/ohmydebn-skill ~/.claude/skills/ohmydebn

  touch $SKILL_STATE
fi
