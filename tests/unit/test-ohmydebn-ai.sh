#!/bin/bash
#
# Unit tests for bin/ohmydebn-ai (Super+A's target) and
# bin/ohmydebn-ai-set-default (what bin/ohmydebn-menu's show_ai_menu
# calls on every AI pick to record it as the new default - see that
# function's own comment). ohmydebn-ai must default to opencode - Super+A's
# original, hardcoded target - whenever nothing's been picked yet or the
# stored value isn't one of the six known names, so a corrupted/foreign
# value can't silently break the shortcut.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_SCRIPT="$REPO_ROOT/bin/ohmydebn-ai"
SET_DEFAULT_SCRIPT="$REPO_ROOT/bin/ohmydebn-ai-set-default"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-ai / bin/ohmydebn-ai-set-default ==="

setup_mocks() {
  for cmd in ohmydebn-opencode ohmydebn-claude-code ohmydebn-chatgpt ohmydebn-pi ohmydebn-code ohmydebn-antigravity; do
    mock_bin "$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >>"\$MOCK_CALLS"
EOF
  done
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

# --- Each of the six valid stored names maps to the matching launcher ---
declare -A EXPECTED=(
  [opencode]="ohmydebn-opencode"
  [claude-code]="ohmydebn-claude-code"
  [chatgpt]="ohmydebn-chatgpt"
  [pi]="ohmydebn-pi"
  [vscode]="ohmydebn-code"
  [antigravity]="ohmydebn-antigravity"
)
for stored in "${!EXPECTED[@]}"; do
  fresh_scratch_home
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
  echo "$stored" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
  run_ai
  assert_contains "stored '$stored' launches ${EXPECTED[$stored]}" "$(cat "$MOCK_CALLS")" "${EXPECTED[$stored]}"
done

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

for name in opencode claude-code chatgpt pi vscode antigravity; do
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
