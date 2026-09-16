#!/bin/bash

# Link the OhMyDebn skill into every user-level skills directory the AI
# coding agents OhMyDebn ships (or that users commonly run) scan. One link
# per directory, all pointing at the packaged skill, so an apt upgrade of
# the skill content reaches every agent at once. Where each agent looks
# (per its docs; Pi's ship in /usr/lib/ohmydebn-pi-coding-agent/docs):
#
#   ~/.claude/skills                     Claude Code. OpenCode reads it too.
#   ~/.gemini/antigravity/global_skills  Antigravity - reads nothing else.
#   ~/.agents/skills                     The Agent Skills spec's shared,
#                                        vendor-neutral directory: Pi and
#                                        OpenCode scan it (Codex, Amp,
#                                        Cursor, Copilot CLI and Gemini CLI
#                                        do as well). Pi does NOT read
#                                        ~/.claude/skills unless a user
#                                        opts in via its settings - which
#                                        is how Pi went without the skill
#                                        before this directory was added.
#
# Idempotent by inspecting the links themselves rather than a one-time
# state marker: a link the user (or an agent's uninstaller) removed comes
# back on the next update, and adding an agent here is one line. A real
# file or directory already at a link path is the user's own and is left
# alone with a note. Runs under install.sh's set -e, so nothing here may
# fail on a normal system.
SKILL_SRC=/usr/share/ohmydebn/config/ohmydebn-skill
SKILL_DIRS=(
  "$HOME/.claude/skills"
  "$HOME/.gemini/antigravity/global_skills"
  "$HOME/.agents/skills"
)

SKILL_HEADLINE_SHOWN=false
for SKILL_DIR in "${SKILL_DIRS[@]}"; do
  SKILL_LINK="$SKILL_DIR/ohmydebn"
  if [ -L "$SKILL_LINK" ] && [ "$(readlink "$SKILL_LINK")" = "$SKILL_SRC" ]; then
    continue
  fi
  if [ "$SKILL_HEADLINE_SHOWN" = false ]; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring OhMyDebn skill for AI coding agents"
    SKILL_HEADLINE_SHOWN=true
  fi
  if [ -e "$SKILL_LINK" ] && [ ! -L "$SKILL_LINK" ]; then
    echo "$SKILL_LINK already exists and is not a symlink - leaving it alone."
    continue
  fi
  echo "Linking $SKILL_LINK -> $SKILL_SRC"
  mkdir -p "$SKILL_DIR"
  # -n: if a stale link to some directory is there, replace the link itself
  # rather than creating a new link inside its target.
  ln -sfn "$SKILL_SRC" "$SKILL_LINK"
done
