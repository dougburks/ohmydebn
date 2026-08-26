#!/bin/bash
#
# Unit tests for bin/ohmydebn-ai-cli (the `a` shell alias's target).
# Mirrors tests/unit/test-ohmydebn-ai.sh's mocking approach for the
# default-lookup/fallback logic, plus coverage specific to ai-cli: the
# three CLI-native tools (opencode/claude-code/pi) launch with no args,
# while the three GUI editors (chatgpt/vscode/antigravity) are launched
# with $PWD so they open on the caller's current directory instead of
# running inside the terminal itself.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_CLI_SCRIPT="$REPO_ROOT/bin/ohmydebn-ai-cli"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-ai-cli ==="

setup_mocks() {
  for cmd in ohmydebn-opencode-cli ohmydebn-claude-code-cli ohmydebn-pi-cli ohmydebn-chatgpt ohmydebn-code ohmydebn-antigravity; do
    mock_bin "$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >>"\$MOCK_CALLS"
EOF
  done
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$AI_CLI_SCRIPT" >"$MOCK_DIR/ohmydebn-ai-cli-patched"
  chmod +x "$MOCK_DIR/ohmydebn-ai-cli-patched"
}

run_ai_cli() {
  : >"$MOCK_CALLS"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/ohmydebn-ai-cli-patched" >"$MOCK_DIR/out" 2>&1
}

fresh_scratch_home() {
  [[ -n "${SCRATCH_HOME:-}" ]] && rm -rf "$SCRATCH_HOME"
  SCRATCH_HOME=$(mktemp -d)
}

mock_init
setup_mocks

# --- No default-ai file at all: falls back to opencode-cli, no args ---
fresh_scratch_home
run_ai_cli
assert_contains "no config file: launches opencode-cli" "$(cat "$MOCK_CALLS")" "ohmydebn-opencode-cli"

# --- CLI-native tools launch their -cli companion with no extra args ---
declare -A CLI_EXPECTED=(
  [opencode]="ohmydebn-opencode-cli"
  [claude-code]="ohmydebn-claude-code-cli"
  [pi]="ohmydebn-pi-cli"
)
for stored in "${!CLI_EXPECTED[@]}"; do
  fresh_scratch_home
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
  echo "$stored" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
  run_ai_cli
  CALLS=$(cat "$MOCK_CALLS")
  assert_eq "stored '$stored' launches ${CLI_EXPECTED[$stored]} with no args" "${CLI_EXPECTED[$stored]} " "$CALLS"
done

# --- GUI editors launch on $PWD instead of running in the terminal ---
declare -A GUI_EXPECTED=(
  [chatgpt]="ohmydebn-chatgpt"
  [vscode]="ohmydebn-code"
  [antigravity]="ohmydebn-antigravity"
)
for stored in "${!GUI_EXPECTED[@]}"; do
  fresh_scratch_home
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
  echo "$stored" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
  run_ai_cli
  assert_eq "stored '$stored' opens ${GUI_EXPECTED[$stored]} on \$PWD" "${GUI_EXPECTED[$stored]} $PWD" "$(cat "$MOCK_CALLS")"
done

# --- A corrupted/unknown stored value falls back to opencode-cli rather than erroring ---
fresh_scratch_home
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
echo "some-garbage-value" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
run_ai_cli
assert_contains "unknown stored value falls back to opencode-cli" "$(cat "$MOCK_CALLS")" "ohmydebn-opencode-cli"

rm -rf "$SCRATCH_HOME"
mock_cleanup

echo
echo "--- GUI wrapper scripts forward args (needed for ai-cli's \$PWD passthrough) ---"
# Each of these calls its real editor by an absolute /usr/... path rather
# than looking it up on PATH, so (unlike the ohmydebn-* scripts above) a
# plain PATH mock won't intercept it - the script itself has to be
# sed-patched to point at the mock instead, same trick ai-cli's own test
# above uses for /usr/share/ohmydebn/bin.

check_forwards_arg() {
  local script="$1" real_bin_path="$2" mock_name="$3"
  mock_init
  mock_bin dpkg <<'EOF'
#!/bin/bash
exit 0
EOF
  mock_bin "$mock_name" <<EOF
#!/bin/bash
echo "$mock_name \$*" >>"\$MOCK_CALLS"
EOF
  sed "s#$real_bin_path#$MOCK_BIN/$mock_name#g" "$script" >"$MOCK_DIR/patched"
  chmod +x "$MOCK_DIR/patched"
  : >"$MOCK_CALLS"
  PATH="$(mock_path)" bash "$MOCK_DIR/patched" /some/dir >/dev/null 2>&1
  assert_eq "$(basename "$script") forwards its arg to $real_bin_path" "$mock_name /some/dir" "$(cat "$MOCK_CALLS")"
  mock_cleanup
}

check_forwards_arg "$REPO_ROOT/bin/ohmydebn-chatgpt" "/usr/bin/chatgpt" chatgpt
check_forwards_arg "$REPO_ROOT/bin/ohmydebn-code" "/usr/bin/code" code
check_forwards_arg "$REPO_ROOT/bin/ohmydebn-antigravity" "/usr/share/antigravity/bin/antigravity" antigravity

test_summary
