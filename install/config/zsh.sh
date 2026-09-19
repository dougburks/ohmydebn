#!/bin/bash

if ! dpkg -s "zsh" >/dev/null 2>&1; then
  exit 0
fi

ZSHRC_STATE=~/.local/state/ohmydebn-config/zshrc-20260116
if [ ! -f $ZSHRC_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring Zsh"
  ZSHRC=~/.zshrc
  if [ -f $ZSHRC ]; then
    mv "$ZSHRC" "$ZSHRC-backup-$(date +%Y%m%d-%H%M%S)"
  fi
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/.zshrc $ZSHRC
  mkdir -p ~/.local/state/ohmydebn-config
  touch $ZSHRC_STATE
fi

for FILE in ~/.bashrc ~/.xsessionrc ~/.zshrc; do
  touch "$FILE"

  # ~/.xsessionrc is sourced by /etc/X11/Xsession under /bin/sh, notably for
  # XRDP sessions. Older OhMyDebn installs appended a Bash/Zsh-only [[ ... ]]
  # PATH block there, which makes remote desktop sessions exit right after
  # login. Migrate that old block out before appending the POSIX-sh version.
  python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1]).expanduser()
content = path.read_text()
old_block = '''
# Update PATH to include OhMyDebn binaries
if ! [[ "$PATH" =~ "/usr/share/ohmydebn/bin:" ]]; then
  export PATH="/usr/share/ohmydebn/bin:$PATH"
fi
'''
for candidate in (old_block, old_block.lstrip('\n')):
    content = content.replace(candidate, '\n')
path.write_text(content)
PY

  if ! grep -F '# Update PATH to include OhMyDebn binaries' "$FILE" >/dev/null 2>&1; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Updating PATH in $FILE"
    cat <<'EOF' >>"$FILE"

# Update PATH to include OhMyDebn binaries
case ":$PATH:" in
  *:/usr/share/ohmydebn/bin:*) ;;
  *) export PATH="/usr/share/ohmydebn/bin:$PATH" ;;
esac
EOF
  fi
done

GRC_STATE=~/.local/state/ohmydebn-config/grc
if [ ! -f $GRC_STATE ]; then
  cat <<EOF >>~/.zshrc

# Use grc to colorize some standard commands
[[ -s "/etc/grc.zsh" ]] && source /etc/grc.zsh
EOF
  touch $GRC_STATE
fi

COLOR_MAN_STATE=~/.local/state/ohmydebn-config/color-man
if [ ! -f $COLOR_MAN_STATE ]; then
  cat <<EOF >>~/.zshrc

# Color man pages with bat
export MANROFFOPT="-c"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
EOF
  touch $COLOR_MAN_STATE
fi

PI_ALIAS_STATE=~/.local/state/ohmydebn-config/pi-alias
if [ ! -f $PI_ALIAS_STATE ]; then
  cat <<EOF >>~/.zshrc

# Pi CLI coding agent, run in the current terminal
alias pi='/usr/share/ohmydebn/bin/ohmydebn-pi-cli'
EOF
  touch $PI_ALIAS_STATE
fi

CODEX_ALIAS_STATE=~/.local/state/ohmydebn-config/codex-alias
if [ ! -f $CODEX_ALIAS_STATE ]; then
  cat <<EOF >>~/.zshrc

# Codex (OpenAI) CLI coding agent, run in the current terminal
alias codex='/usr/share/ohmydebn/bin/ohmydebn-codex-cli'
EOF
  touch $CODEX_ALIAS_STATE
fi

OPENCODE_CLI_ALIAS_STATE=~/.local/state/ohmydebn-config/opencode-cli-alias
if [ ! -f $OPENCODE_CLI_ALIAS_STATE ]; then
  sed -i "s#^alias c='/usr/bin/opencode-cli'\$#alias c='/usr/share/ohmydebn/bin/ohmydebn-opencode-cli'#" ~/.zshrc
  touch $OPENCODE_CLI_ALIAS_STATE
fi

CLAUDE_ALIAS_STATE=~/.local/state/ohmydebn-config/claude-alias
if [ ! -f $CLAUDE_ALIAS_STATE ]; then
  cat <<EOF >>~/.zshrc

# Claude Code CLI, run in the current terminal
alias claude='/usr/share/ohmydebn/bin/ohmydebn-claude-code-cli'
EOF
  touch $CLAUDE_ALIAS_STATE
fi

AI_CLI_ALIAS_STATE=~/.local/state/ohmydebn-config/ai-cli-alias
if [ ! -f $AI_CLI_ALIAS_STATE ]; then
  cat <<EOF >>~/.zshrc

# Default AI assistant, run in the current terminal (or opened on \$PWD for
# GUI defaults like VS Code/Antigravity/ChatGPT)
alias a='/usr/share/ohmydebn/bin/ohmydebn-ai-cli'
EOF
  touch $AI_CLI_ALIAS_STATE
fi
