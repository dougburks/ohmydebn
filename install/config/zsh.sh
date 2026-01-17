#!/bin/bash

ZSHRC_STATE=~/.local/state/ohmydebn-config/zshrc-20260116
if [ ! -f $ZSHRC_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring Zsh"
  ZSHRC=~/.zshrc
  if [ -f $ZSHRC ]; then
    mv $ZSHRC $ZSHRC-backup-$(date +%Y%m%d-%H%M%S)
  fi
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/.zshrc $ZSHRC
  mkdir -p ~/.local/state/ohmydebn-config
  touch $ZSHRC_STATE
fi

for FILE in ~/.bashrc ~/.xsessionrc ~/.zshrc; do
  if ! grep "/usr/share/ohmydebn/bin" $FILE >/dev/null 2>&1; then
    /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Updating PATH in $FILE"
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
