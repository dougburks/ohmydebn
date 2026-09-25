#!/bin/bash
#
# Unit tests for choosing the default AI assistant (what Super+A and the `a`
# alias launch): bin/ohmydebn-ai-set-default's --current/--list-installed/
# --ask, an AI installer's "make it your default?" question (Codex's stands
# in for all of them - tests/consistency.sh checks every installer asks with
# its own name), and bin/ohmydebn-menu's Setup > Defaults > Agent and
# Browser pickers, which list only what's installed and mark the current
# default. dpkg/sudo/apt/notify-send and the menu picker are mocked, so
# nothing here touches the real system or the user's real default.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== default AI assistant: ohmydebn-ai-set-default, installers, Setup > Defaults ==="

# setup <space-separated installed dpkg packages>
setup() {
  local installed="$1"
  mock_init
  mock_bin dpkg <<EOF2
#!/bin/bash
[[ "\$1" == "-s" && " $installed " == *" \$2 "* ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF2
  SCRATCH_HOME=$(mktemp -d)
  DEFAULT_FILE="$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
  for script in ohmydebn-ai-set-default ohmydebn-codex-install ohmydebn-browser-set-default; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

run_set_default() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-ai-set-default" "$@"
}

# --- --current falls back to opencode when unset or unrecognized ---
setup ""
assert_eq "--current with nothing stored is opencode" "opencode" "$(run_set_default --current)"
mkdir -p "$(dirname "$DEFAULT_FILE")"
echo "bogus" >"$DEFAULT_FILE"
assert_eq "--current with an unknown stored name is opencode" "opencode" "$(run_set_default --current)"
echo "t3code" >"$DEFAULT_FILE"
assert_eq "--current returns the stored name" "t3code" "$(run_set_default --current)"
teardown

# --- plain set records the name; an unknown name is rejected ---
setup ""
run_set_default codex >/dev/null 2>&1
assert_eq "set: records the name" "codex" "$(cat "$DEFAULT_FILE")"
run_set_default bogus >/dev/null 2>&1
assert_eq "set: an unknown name exits non-zero" "1" "$?"
assert_eq "set: an unknown name leaves the default alone" "codex" "$(cat "$DEFAULT_FILE")"
teardown

# --- --list-installed lists only installed tools, by their package ---
setup "claude-code ohmydebn-t3code code"
LIST=$(run_set_default --list-installed)
assert_eq "--list-installed: only installed tools, name<TAB>display name" \
  "$(printf 'claude-code\tClaude Code\nt3code\tT3 Code\nvscode\tVS Code')" "$LIST"
teardown

# --- --ask: "y" sets it, anything else (including a bare Enter) keeps the old one ---
for answer in y Y yes; do
  setup "ohmydebn-codex-cli"
  OUT=$(printf '%s\n' "$answer" | run_set_default --ask codex 2>&1)
  assert_eq "--ask '$answer': makes it the default" "codex" "$(cat "$DEFAULT_FILE" 2>/dev/null)"
  assert_contains "--ask '$answer': says so" "$OUT" "Codex is now your default AI assistant."
  teardown
done
for answer in "" n no; do
  setup "ohmydebn-codex-cli"
  mkdir -p "$(dirname "$DEFAULT_FILE")"
  echo "claude-code" >"$DEFAULT_FILE"
  OUT=$(printf '%s\n' "$answer" | run_set_default --ask codex 2>&1)
  assert_eq "--ask '$answer': keeps the current default" "claude-code" "$(cat "$DEFAULT_FILE")"
  assert_contains "--ask '$answer': says where to change it later" "$OUT" "OhMyDebn Menu > Setup > Defaults > Agent"
  teardown
done

# --- --ask stays quiet when it's already the default (Super+A installing its own default) ---
setup "ohmydebn-opencode-cli"
OUT=$(run_set_default --ask opencode </dev/null 2>&1)
assert_eq "--ask for the (fallback) current default asks nothing" "" "$OUT"
assert_eq "--ask for the current default writes nothing" "no" "$([[ -f "$DEFAULT_FILE" ]] && echo yes || echo no)"
teardown

# --- --ask stays quiet when the install didn't actually happen ---
setup ""
OUT=$(printf 'y\n' | run_set_default --ask chatgpt 2>&1)
assert_eq "--ask for a tool that isn't installed asks nothing" "" "$OUT"
teardown

# --- an installer run from the menu asks, after installing; --skip-prompt never asks ---
setup ""
# dpkg reports Codex missing until apt has "installed" it.
mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn-codex-cli" && -f "$MOCK_DIR/installed" ]] && exit 0
exit 1
EOF2
mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$*" == *"install ohmydebn-codex-cli"* ]] && touch "$MOCK_DIR/installed"
exit 0
EOF2
OUT=$(printf '\ny\n' | HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-codex-install" 2>&1)
assert_contains "menu install: installs Codex" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y install ohmydebn-codex-cli"
assert_contains "menu install: asks about the default" "$OUT" "Make Codex your default AI assistant (Super + A)? [y/N]"
assert_eq "menu install: 'y' makes it the default" "codex" "$(cat "$DEFAULT_FILE" 2>/dev/null)"
rm -f "$MOCK_DIR/installed" "$DEFAULT_FILE"
OUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-codex-install" --skip-prompt </dev/null 2>&1)
assert_not_contains "--skip-prompt install: never asks" "$OUT" "default AI assistant"
assert_eq "--skip-prompt install: default unchanged" "no" "$([[ -f "$DEFAULT_FILE" ]] && echo yes || echo no)"
teardown

# --- Setup > Defaults > Agent / Browser pickers ---
# setup_picker: pulls the pick_default_* functions out of ohmydebn-menu with
# their helper paths pointed at mocks, and stubs menu() to "pick" $PICK.
setup_picker() {
  mock_init
  mock_bin ohmydebn-ai-set-default <<'EOF2'
#!/bin/bash
case "$1" in
--current) echo codex ;;
--list-installed) printf 'opencode\tOpenCode\ncodex\tCodex\nt3code\tT3 Code\n' ;;
*) mock_log "ai-set-default $*" ;;
esac
EOF2
  mock_bin ohmydebn-browser-set-default <<'EOF2'
#!/bin/bash
case "$1" in
--current) echo firefox-esr ;;
--list-installed) printf 'brave-origin\tBrave Origin\nfirefox-esr\tFirefox\n' ;;
esac
EOF2
  mock_bin notify-send <<'EOF2'
#!/bin/bash
mock_log "notify $2"
EOF2
  sed -n '/^pick_default_agent() {/,/^}/p;/^pick_default_browser() {/,/^}/p' "$REPO_ROOT/bin/ohmydebn-menu" |
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" >"$MOCK_DIR/pickers.sh"
}

run_picker() {
  local func="$1" pick="$2"
  PATH="$(mock_path)" PICK="$pick" bash -c '
    source "$MOCK_DIR/pickers.sh"
    menu() { mock_log "items $2"; MENU_RESULT="$PICK"; }
    show_defaults_menu() { mock_log "back"; }
    present_terminal() { mock_log "terminal $1 | $2"; }
    '"$func"
}

AI_ICON=$(printf '\U000f16a4')
WEB_ICON=$(printf '\U000f059f')

setup_picker
run_picker pick_default_agent "$AI_ICON  T3 Code"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "agent picker: lists installed tools, current one marked" "$CALLS" \
  "items $AI_ICON  OpenCode\\n$AI_ICON  Codex (current default)\\n$AI_ICON  T3 Code"
assert_contains "agent picker: picking one sets it" "$CALLS" "ai-set-default t3code"
assert_contains "agent picker: confirms with a notification" "$CALLS" "notify T3 Code is now your default AI assistant (Super + A)."
mock_cleanup

setup_picker
run_picker pick_default_agent "$AI_ICON  Codex (current default)"
assert_contains "agent picker: the marked entry maps back to its tool" "$(cat "$MOCK_CALLS")" "ai-set-default codex"
mock_cleanup

setup_picker
OUT=$(run_picker pick_default_agent "" 2>&1)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "agent picker: Back returns to Defaults" "$CALLS" "back"
assert_not_contains "agent picker: Back sets nothing" "$CALLS" "ai-set-default"
assert_eq "agent picker: Back prints no errors" "" "$OUT"
mock_cleanup

setup_picker
run_picker pick_default_browser "$WEB_ICON  Brave Origin"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "browser picker: lists installed browsers, current one marked" "$CALLS" \
  "items $WEB_ICON  Brave Origin\\n$WEB_ICON  Firefox (current default)"
assert_contains "browser picker: sets it in a terminal (needs sudo)" "$CALLS" \
  "terminal Default Browser | $MOCK_BIN/ohmydebn-browser-set-default brave-origin"
mock_cleanup

# --- ohmydebn-browser-set-default --list-installed / --current ---
setup "brave-origin firefox-esr"
mock_bin snap <<'EOF2'
#!/bin/bash
exit 1
EOF2
mock_bin xdg-settings <<'EOF2'
#!/bin/bash
[[ "$1 $2" == "get default-web-browser" ]] && echo firefox-esr.desktop
EOF2
assert_eq "browser --list-installed: only installed browsers" \
  "$(printf 'brave-origin\tBrave Origin\nfirefox-esr\tFirefox')" \
  "$(PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-browser-set-default" --list-installed)"
assert_eq "browser --current: maps the xdg default back to its package" "firefox-esr" \
  "$(PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-browser-set-default" --current)"
teardown

test_summary
