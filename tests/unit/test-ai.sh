#!/bin/bash
#
# Unit tests for bin/ohmydebn-ai's default-assistant resolution and
# dispatch - the sole entry point for Super+A and every menu pick now
# that ohmydebn-ai-tiled has been retired (all six assistants tile
# themselves via gTile-OhMyDebn's own window-created auto-tile handler,
# matching against /usr/share/ohmydebn/config/tile-rules.json, so there's
# no separate tiled variant left to wrap this dispatch).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-ai"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-ai ==="

run_with_default() {
  local scratch_home="$1" stored="$2"
  for app in opencode claude-code chatgpt pi code antigravity; do
    mock_bin "ohmydebn-$app" <<EOF
#!/bin/bash
mock_log "ohmydebn-$app"
EOF
  done
  if [[ -n "$stored" ]]; then
    mkdir -p "$scratch_home/.config/ohmydebn/current"
    echo "$stored" >"$scratch_home/.config/ohmydebn/current/default-ai"
  fi
  local sed_args=()
  for app in opencode claude-code chatgpt pi code antigravity; do
    sed_args+=(-e "s#/usr/share/ohmydebn/bin/ohmydebn-$app#$MOCK_BIN/ohmydebn-$app#g")
  done
  sed "${sed_args[@]}" "$SCRIPT" >"$MOCK_DIR/ai-patched.sh"
  HOME="$scratch_home" bash "$MOCK_DIR/ai-patched.sh" >/dev/null 2>&1
}

test_default() {
  local stored="$1" expect_bin="$2" name="$3"
  mock_init
  local scratch_home
  scratch_home=$(mktemp -d)
  run_with_default "$scratch_home" "$stored"
  assert_contains "$name" "$(cat "$MOCK_CALLS")" "$expect_bin"
  rm -rf "$scratch_home"
  mock_cleanup
}

test_default "opencode" "ohmydebn-opencode" "opencode: execs ohmydebn-opencode"
test_default "claude-code" "ohmydebn-claude-code" "claude-code: execs ohmydebn-claude-code"
test_default "chatgpt" "ohmydebn-chatgpt" "chatgpt: execs ohmydebn-chatgpt"
test_default "pi" "ohmydebn-pi" "pi: execs ohmydebn-pi"
test_default "vscode" "ohmydebn-code" "vscode: execs ohmydebn-code"
test_default "antigravity" "ohmydebn-antigravity" "antigravity: execs ohmydebn-antigravity"
test_default "" "ohmydebn-opencode" "no default file: falls back to opencode"
test_default "not-a-real-assistant" "ohmydebn-opencode" "unrecognized default: falls back to opencode"

test_summary
