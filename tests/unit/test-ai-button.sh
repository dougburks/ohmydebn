#!/bin/bash
#
# Unit tests for the panel's AI button (the robot after the OhMyDebn
# Menu's grin): bin/ohmydebn-menu's ai_button_menu, which opens the
# assistant Super + A opens, starts it on making a theme or an app, or
# offers the others; and the starting prompt reaching each terminal
# assistant through its launcher and run script. The menu picker,
# ohmydebn-ai, dpkg and the assistants themselves are stand-ins that log,
# so nothing is installed or run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== the AI button: ai_button_menu, and starting prompts ==="

AI_ICON=$(printf '\U000f16a4')
THEME_ICON=$(printf '\U000f03d8')
APP_ICON=$(printf '\U000f08c6')

# setup_button <what ohmydebn-ai --which prints>: ai_button_menu and its
# prompts, pulled out of ohmydebn-menu with their paths pointed at mocks.
setup_button() {
  mock_init
  mock_bin ohmydebn-ai <<EOF
#!/bin/bash
if [ "\$1" = --which ]; then echo "$1"; exit 0; fi
mock_log "ai \$*"
EOF
  mock_bin ohmydebn-ai-set-default <<'EOF'
#!/bin/bash
[ "$1" = --display-name ] && [ "$2" = claude-code ] && echo "Claude Code"
EOF
  {
    grep -E '^AI_(THEME|APP)_PROMPT=' "$REPO_ROOT/bin/ohmydebn-menu"
    sed -n '/^ai_button_menu() {/,/^}/p' "$REPO_ROOT/bin/ohmydebn-menu"
  } | sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" >"$MOCK_DIR/button.sh"
}

# press <row picked, or empty for Escape>: CALLS holds what it did.
press() {
  PATH="$(mock_path)" PICK="$1" bash -c '
    source "$MOCK_DIR/button.sh"
    menu() { mock_log "menu $1 | $2"; MENU_RESULT="$PICK"; }
    show_ai_menu() { mock_log "apps > ai"; }
    ai_button_menu' </dev/null
  CALLS=$(cat "$MOCK_CALLS")
}

setup_button claude-code
press ""
assert_contains "rows: open the current assistant by name, the starters, then the others" "$CALLS" \
  "menu AI | $AI_ICON  Open Claude Code\\n$THEME_ICON  Make a theme\\n$APP_ICON  Make an app\\n  Choose another assistant"
assert_not_contains "Escape: nothing opened" "$CALLS" "ai "
mock_cleanup

setup_button claude-code
press "$AI_ICON  Open Claude Code"
assert_contains "Open: Super + A's assistant, no prompt" "$(grep '^ai' <<<"$CALLS")" "ai "
assert_eq "Open: exactly one launch, without a prompt" "ai " "$(grep '^ai' <<<"$CALLS")"
mock_cleanup

setup_button claude-code
press "$THEME_ICON  Make a theme"
assert_contains "Make a theme: the assistant gets the theme request" "$CALLS" "ai Make me a new OhMyDebn theme."
assert_contains "Make a theme: it asks first, then follows the skill's theme guide" "$CALLS" \
  "Ask me what look or inspiration I have in mind, then build it following the OhMyDebn skill's guide to making a new theme"
mock_cleanup

setup_button claude-code
press "$APP_ICON  Make an app"
assert_contains "Make an app: the assistant gets the app request" "$CALLS" "ai Make me a new app for my OhMyDebn desktop."
assert_contains "Make an app: it follows the skill's app guide" "$CALLS" "the OhMyDebn skill's guide to making an app"
mock_cleanup

setup_button claude-code
press "  Choose another assistant"
assert_contains "Choose another: Apps > AI" "$CALLS" "apps > ai"
mock_cleanup

# Nothing chosen and OpenCode not installed: the first row offers the list.
setup_button ""
press ""
assert_contains "none yet: the first row offers the list" "$CALLS" "menu AI | $AI_ICON  Choose an AI assistant\\n$THEME_ICON  Make a theme"
assert_not_contains "none yet: no Choose another row as well" "$CALLS" "Choose another"
mock_cleanup

# The name the Open row shows comes from ohmydebn-ai-set-default.
assert_eq "--display-name: the name people see" "Claude Code" \
  "$(HOME=$(mktemp -d) bash "$REPO_ROOT/bin/ohmydebn-ai-set-default" --display-name claude-code)"
if bash "$REPO_ROOT/bin/ohmydebn-ai-set-default" --display-name nonsense >/dev/null 2>&1; then
  assert_eq "--display-name: an unknown name is a usage error" "error" "accepted"
else
  assert_eq "--display-name: an unknown name is a usage error" "error" "error"
fi

# The skill has the guides the prompts name.
SKILL="$REPO_ROOT/config/ohmydebn-skill/SKILL.md"
assert_eq "the skill has a guide to making a new theme" "yes" "$(grep -q '^### Pattern [0-9]*: Make a new theme' "$SKILL" && echo yes || echo no)"
assert_eq "the skill has a guide to making an app" "yes" "$(grep -q '^### Pattern [0-9]*: Make an app' "$SKILL" && echo yes || echo no)"

# --- Starting prompts reach each terminal assistant ---
# agent: launcher name, run script's binary, how the prompt is passed.
AGENTS=(
  "claude-code|/usr/bin/claude|-- Make me a theme"
  "codex|/usr/lib/ohmydebn-codex-cli/bin/codex|-- Make me a theme"
  "opencode|/usr/bin/opencode-cli|--prompt Make me a theme"
  "grok|/usr/lib/ohmydebn-grok-build/grok|-- Make me a theme"
  "pi|/usr/lib/ohmydebn-pi-coding-agent/pi|-- Make me a theme"
  "omp|/usr/lib/ohmydebn-oh-my-pi/omp|-- Make me a theme"
)
for entry in "${AGENTS[@]}"; do
  IFS='|' read -r agent binary expected <<<"$entry"
  mock_init
  SCRATCH_HOME=$(mktemp -d)
  printf '#!/bin/bash\nexit 0\n' | mock_bin dpkg
  printf '#!/bin/bash\nmock_log "agent $*"\n' | mock_bin agent-binary
  printf '#!/bin/bash\nmock_log "terminal $*"\n' | mock_bin ohmydebn-terminal
  sed -e "s#$binary#$MOCK_BIN/agent-binary#g" -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" \
    "$REPO_ROOT/bin/ohmydebn-$agent-run" >"$MOCK_DIR/run"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-$agent" >"$MOCK_DIR/launcher"

  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/run" "Make me a theme" </dev/null >/dev/null 2>&1
  assert_eq "$agent: a starting prompt is passed as $expected" "agent $expected" "$(cat "$MOCK_CALLS")"
  : >"$MOCK_CALLS"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/run" </dev/null >/dev/null 2>&1
  assert_eq "$agent: without one, it starts as before" "agent " "$(cat "$MOCK_CALLS")"
  : >"$MOCK_CALLS"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/launcher" "Make me a theme" </dev/null >/dev/null 2>&1
  assert_contains "$agent: the launcher hands the prompt to its run script" "$(cat "$MOCK_CALLS")" \
    "ohmydebn-$agent-run Make me a theme"
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
done

test_summary
