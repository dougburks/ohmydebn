#!/bin/bash

if [ ! -f ~/.zshrc ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "cat" "Configuring Zsh"
  cp /usr/share/ohmydebn/config/.zshrc ~/
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
