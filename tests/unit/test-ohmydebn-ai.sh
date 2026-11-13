#!/bin/bash
#
# Unit tests for bin/ohmydebn-ai (Super+A's target) and
# bin/ohmydebn-ai-set-default (what bin/ohmydebn-menu's show_ai_menu
# calls on every AI pick to record it as the new default - see that
# function's own comment). ohmydebn-ai must default to opencode - Super+A's
# original, hardcoded target - whenever nothing's been picked yet or the
# stored value isn't one of the known names, so a corrupted/foreign
# value can't silently break the shortcut.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_SCRIPT="$REPO_ROOT/bin/ohmydebn-ai"
SET_DEFAULT_SCRIPT="$REPO_ROOT/bin/ohmydebn-ai-set-default"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-ai / bin/ohmydebn-ai-set-default ==="

setup_mocks() {
  for cmd in ohmydebn-opencode ohmydebn-opencode-desktop ohmydebn-claude-code ohmydebn-claude-desktop ohmydebn-chatgpt ohmydebn-codex ohmydebn-grok ohmydebn-crush ohmydebn-omp ohmydebn-pi ohmydebn-t3code ohmydebn-code; do
    mock_bin "$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >>"\$MOCK_CALLS"
EOF
  done
  # OpenCode installed unless a test says otherwise (MOCK_NO_OPENCODE=1).
  mock_bin dpkg <<'EOF'
#!/bin/bash
[ "$1" = -s ] && [ "$2" = ohmydebn-opencode-cli ] && [ -z "${MOCK_NO_OPENCODE:-}" ] && exit 0
exit 1
EOF
  mock_bin notify-send <<'EOF'
#!/bin/bash
echo "notify-send $*" >>"$MOCK_CALLS"
EOF
  mock_bin ohmydebn-menu <<'EOF'
#!/bin/bash
echo "ohmydebn-menu $*" >>"$MOCK_CALLS"
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$AI_SCRIPT" >"$MOCK_DIR/ohmydebn-ai-patched"
  chmod +x "$MOCK_DIR/ohmydebn-ai-patched"
}

run_ai() {
  : >"$MOCK_CALLS"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/ohmydebn-ai-patched" >"$MOCK_DIR/out" 2>&1
}

fresh_scratch_home() {
  [[ -n "${SCRATCH_HOME:-}" ]] && rm -rf "$SCRATCH_HOME"
  SCRATCH_HOME=$(mktemp -d)
}

mock_init
setup_mocks

# --- No default-ai file at all: falls back to opencode ---
fresh_scratch_home
run_ai
assert_contains "no config file: launches opencode" "$(cat "$MOCK_CALLS")" "ohmydebn-opencode"

# --- Nothing chosen and OpenCode not installed (a new user, or the panel's
# AI button on a fresh install): every assistant is offered, not just an
# OpenCode install prompt ---
fresh_scratch_home
MOCK_NO_OPENCODE=1 run_ai
assert_contains "nothing chosen or installed: opens the menu on Apps > AI" "$(cat "$MOCK_CALLS")" "ohmydebn-menu ai"
assert_contains "nothing chosen or installed: says what to do" "$(cat "$MOCK_CALLS")" "Choose an AI assistant"
assert_not_contains "nothing chosen or installed: no OpenCode install prompt" "$(cat "$MOCK_CALLS")" "ohmydebn-opencode"

# --- A chosen default that isn't installed yet still opens (and installs) it ---
fresh_scratch_home
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
echo "claude-code" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
MOCK_NO_OPENCODE=1 run_ai
assert_eq "chosen default, OpenCode absent: opens the chosen one" "ohmydebn-claude-code " "$(cat "$MOCK_CALLS")"

# --- Each of the valid stored names maps to the matching launcher ---
declare -A EXPECTED=(
  [opencode]="ohmydebn-opencode"
  [claude-code]="ohmydebn-claude-code"
  [claude-desktop]="ohmydebn-claude-desktop"
  [opencode-desktop]="ohmydebn-opencode-desktop"
  [chatgpt]="ohmydebn-chatgpt"
  [codex]="ohmydebn-codex"
  [grok]="ohmydebn-grok"
  [crush]="ohmydebn-crush"
  [omp]="ohmydebn-omp"
  [pi]="ohmydebn-pi"
  [t3code]="ohmydebn-t3code"
  [vscode]="ohmydebn-code"
)
for stored in "${!EXPECTED[@]}"; do
  fresh_scratch_home
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
  echo "$stored" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
  run_ai
  assert_contains "stored '$stored' launches ${EXPECTED[$stored]}" "$(cat "$MOCK_CALLS")" "${EXPECTED[$stored]}"
done

# --- Antigravity, no longer offered (4.15.0), falls back like any unknown value ---
fresh_scratch_home
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
echo "antigravity" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
run_ai
assert_eq "stored 'antigravity' (no longer offered) launches OpenCode" "ohmydebn-opencode " "$(cat "$MOCK_CALLS")"
if HOME="$SCRATCH_HOME" bash "$SET_DEFAULT_SCRIPT" antigravity >/dev/null 2>&1; then
  assert_eq "antigravity can no longer be chosen as the default" "rejected" "accepted"
else
  assert_eq "antigravity can no longer be chosen as the default" "rejected" "rejected"
fi

# --- A corrupted/unknown stored value falls back to opencode rather than erroring ---
fresh_scratch_home
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
echo "some-garbage-value" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
run_ai
assert_contains "unknown stored value falls back to opencode" "$(cat "$MOCK_CALLS")" "ohmydebn-opencode"

rm -rf "$SCRATCH_HOME"

echo
echo "--- ohmydebn-ai-set-default ---"

set_default() {
  fresh_scratch_home
  HOME="$SCRATCH_HOME" bash "$SET_DEFAULT_SCRIPT" "$1" >/dev/null 2>&1
}

for name in opencode opencode-desktop claude-code claude-desktop chatgpt codex grok crush omp pi t3code vscode; do
  if ! set_default "$name"; then
    assert_eq "accepts valid name '$name'" "accepted" "rejected"
  else
    assert_eq "accepts valid name '$name'" "accepted" "accepted"
  fi
  assert_eq "writes '$name' to default-ai" "$name" "$(cat "$SCRATCH_HOME/.config/ohmydebn/current/default-ai" 2>/dev/null)"
done

for bad in "" "OpenCode" "opencode; rm -rf /" "../../etc/passwd"; do
  if set_default "$bad"; then
    assert_eq "rejects invalid name '$bad'" "rejected" "accepted"
  else
    assert_eq "rejects invalid name '$bad'" "rejected" "rejected"
  fi
  assert_eq "invalid name '$bad' writes no file" "" "$(cat "$SCRATCH_HOME/.config/ohmydebn/current/default-ai" 2>/dev/null)"
done

rm -rf "$SCRATCH_HOME"
mock_cleanup
test_summary
