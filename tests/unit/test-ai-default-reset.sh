#!/bin/bash
#
# Unit tests for install/config/ai-default.sh: a default AI assistant of
# antigravity, which OhMyDebn stopped offering in 4.15.0, is cleared once
# on update with a note, so Super+A and the `a` alias fall back to OpenCode
# openly and the doctor doesn't flag it. Any other default is left alone.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STEP="$REPO_ROOT/install/config/ai-default.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/ai-default.sh ==="

# run_step <stored default, or "" for no file>
run_step() {
  mock_init
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "headline $*"
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$STEP" >"$MOCK_DIR/step.sh"
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
  DEFAULT_FILE="$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
  [[ -n "$1" ]] && echo "$1" >"$DEFAULT_FILE"
  OUTPUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash -e "$MOCK_DIR/step.sh" 2>&1)
  STATUS=$?
}

finish() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

run_step "antigravity"
assert_eq "antigravity: exits 0" "0" "$STATUS"
assert_eq "antigravity: the stored default is cleared" "no" "$([ -e "$DEFAULT_FILE" ] && echo yes || echo no)"
assert_contains "antigravity: says the default is now OpenCode" "$OUTPUT" "your default AI assistant is now OpenCode"
assert_contains "antigravity: says where to choose another" "$OUTPUT" "Setup > Defaults > Agent"
assert_eq "antigravity: Super+A now resolves to OpenCode" "opencode" \
  "$(HOME="$SCRATCH_HOME" bash "$REPO_ROOT/bin/ohmydebn-ai-set-default" --current)"
finish

run_step "claude-code"
assert_eq "another default: kept" "claude-code" "$(cat "$DEFAULT_FILE")"
assert_eq "another default: nothing said" "" "$OUTPUT"
finish

run_step ""
assert_eq "no default set: exits 0" "0" "$STATUS"
assert_eq "no default set: nothing said" "" "$OUTPUT"
assert_eq "no default set: still none" "no" "$([ -e "$DEFAULT_FILE" ] && echo yes || echo no)"
finish

# antigravity is no longer a choice anywhere the default is read.
for f in bin/ohmydebn-ai bin/ohmydebn-ai-cli bin/ohmydebn-ai-set-default bin/ohmydebn-doctor; do
  assert_not_contains "$f: antigravity isn't a default AI choice" "$(grep -E '^\s*(opencode \||ALL_NAMES=)' "$REPO_ROOT/$f")" "antigravity"
done

test_summary
