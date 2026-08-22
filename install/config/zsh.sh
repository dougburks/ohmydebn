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
  if ! grep "/usr/share/ohmydebn/bin" $FILE >/dev/null 2>&1; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "Updating PATH in $FILE"
    cat <<'EOF' >>$FILE

# Update PATH to include OhMyDebn binaries
if ! [[ "$PATH" =~ "/usr/share/ohmydebn/bin:" ]]; then
  export PATH="/usr/share/ohmydebn/bin:$PATH"
fi
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

OPENCODE_CLI_ALIAS_STATE=~/.local/state/ohmydebn-config/opencode-cli-alias
if [ ! -f $OPENCODE_CLI_ALIAS_STATE ]; then
  sed -i "s#^alias c='/usr/bin/opencode-cli'\$#alias c='/usr/share/ohmydebn/bin/ohmydebn-opencode-cli'#" ~/.zshrc
  touch $OPENCODE_CLI_ALIAS_STATE
fi
