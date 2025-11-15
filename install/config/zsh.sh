#!/bin/bash

if [ ! -f ~/.zshrc ]; then
  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Configuring Zsh"
  cp /opt/ohmydebn/config/.zshrc ~/
fi

for FILE in ~/.bashrc ~/.xsessionrc ~/.zshrc; do
  if ! grep "/opt/ohmydebn/bin" $FILE >/dev/null 2>&1; then
    /opt/ohmydebn/bin/ohmydebn-headline "cat" "Updating PATH in $FILE"
    cat <<'EOF' >>$FILE

# Update PATH to include OhMyDebn binaries
if ! [[ "$PATH" =~ "/opt/ohmydebn/bin:" ]]; then
  export PATH="/opt/ohmydebn/bin:$PATH"
fi
EOF
  fi
done
