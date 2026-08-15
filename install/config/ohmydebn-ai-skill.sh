#!/bin/bash

SKILL_STATE_OPENCODE=~/.local/state/ohmydebn-config/skill-20260116
if [ ! -f $SKILL_STATE_OPENCODE ]; then

  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring AI skill for OpenCode"

  # Place in ~/.claude/skills since all tools populate from there as well as their own sources
  mkdir -p ~/.claude/skills
  ln -s /usr/share/ohmydebn/config/ohmydebn-skill ~/.claude/skills/ohmydebn

  touch $SKILL_STATE_OPENCODE
fi

SKILL_STATE_ANTIGRAVITY=~/.local/state/ohmydebn-config/skill-antigravity-20260125
if [ ! -f $SKILL_STATE_ANTIGRAVITY ]; then

  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring AI skill for Antigravity"

  mkdir -p ~/.gemini/antigravity/global_skills
  ln -s /usr/share/ohmydebn/config/ohmydebn-skill ~/.gemini/antigravity/global_skills/ohmydebn

  touch $SKILL_STATE_ANTIGRAVITY
fi
