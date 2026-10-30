#!/bin/bash

if [ ! -d ~/.config/opencode ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Configuring opencode"
  mkdir -p ~/.config
  cp -av /usr/share/ohmydebn/config/opencode ~/.config/
  echo
fi

# OpenCode's "system" theme takes its colors from the terminal, so OpenCode
# follows the OhMyDebn theme. OpenCode 2 reads its theme from cli.json, not
# opencode.json where OhMyDebn used to set it, so existing installs got
# OpenCode's own theme instead. Set it once, never replacing a theme the
# user chose. Before OpenCode 2's first run there's no cli.json: OpenCode
# makes it then from OpenCode 1's tui.json and saved settings (kv.json), so
# the theme goes in tui.json and comes across with the rest (writing
# cli.json here would skip that, losing those settings). A theme picked with
# /themes in OpenCode 1 is in kv.json and comes across by itself. A file jq
# can't read (JSONC with comments) is the user's, and is left alone.
OPENCODE_THEME_STATE=~/.local/state/ohmydebn-config/opencode-system-theme-20261029
if [ ! -f "$OPENCODE_THEME_STATE" ]; then
  # opencode_set_theme <file> <jq filter>: rewrites the file atomically.
  opencode_set_theme() {
    local tmp
    tmp=$(mktemp "$1.XXXXXX") || return 0
    if jq "$2" "$1" >"$tmp" 2>/dev/null; then
      mv -f "$tmp" "$1"
    else
      rm -f "$tmp"
    fi
  }
  OPENCODE_CLI_JSON=~/.config/opencode/cli.json
  OPENCODE_TUI_JSON=~/.config/opencode/tui.json
  if [ -f "$OPENCODE_CLI_JSON" ]; then
    jq -e '.theme.name' "$OPENCODE_CLI_JSON" >/dev/null 2>&1 ||
      opencode_set_theme "$OPENCODE_CLI_JSON" '.theme.name = "system"'
  elif jq -e '.theme' ~/.local/state/opencode/kv.json >/dev/null 2>&1; then
    : # Chosen in OpenCode 1.
  elif [ -f "$OPENCODE_TUI_JSON" ]; then
    jq -e '.theme' "$OPENCODE_TUI_JSON" >/dev/null 2>&1 ||
      opencode_set_theme "$OPENCODE_TUI_JSON" '.theme = "system"'
  else
    mkdir -p ~/.config/opencode
    printf '{\n  "$schema": "https://opencode.ai/tui.json",\n  "theme": "system"\n}\n' >"$OPENCODE_TUI_JSON"
  fi
  mkdir -p ~/.local/state/ohmydebn-config
  touch "$OPENCODE_THEME_STATE"
fi
