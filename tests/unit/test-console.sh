#!/bin/bash
#
# Unit tests for the drop-down console: bin/ohmydebn-console-run (what runs
# inside it) here, and bin/ohmydebn-console's pure logic (which way a key
# press goes, where the window goes) in test-console.py, run at the end.
#
# ohmydebn-console-run runs the default AI's -cli wrapper only when it's a
# terminal assistant that's installed, and always ends in a shell; a
# desktop-app default or a missing assistant gets a note instead, and never
# an installer. The real ohmydebn-ai-set-default answers --current and
# --list-installed, with dpkg mocked, so the names and packages it knows
# are the ones under test.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-console-run ==="

TERMINAL_AIS=(opencode claude-code codex grok crush omp pi)
DESKTOP_AIS=(opencode-desktop claude-desktop chatgpt t3code vscode antigravity)

setup() {
  mock_init
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
  # MOCK_INSTALLED: space-separated packages dpkg -s reports installed.
  mock_bin dpkg <<'EOF'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]]
EOF
  local ai
  for ai in "${TERMINAL_AIS[@]}"; do
    mock_bin "ohmydebn-$ai-cli" <<EOF
#!/bin/bash
mock_log "ran ohmydebn-$ai-cli"
exit \${MOCK_AI_EXIT:-0}
EOF
    # Its installer must never run from the console.
    mock_bin "ohmydebn-$ai-install" <<EOF
#!/bin/bash
mock_log "ran ohmydebn-$ai-install"
EOF
  done
  mock_bin fake-shell <<'EOF'
#!/bin/bash
mock_log "ran the shell"
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-ai-set-default" >"$MOCK_BIN/ohmydebn-ai-set-default"
  chmod +x "$MOCK_BIN/ohmydebn-ai-set-default"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-console-run" >"$MOCK_DIR/console-run"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# run_console <default-ai or ""> <installed packages> [AI exit code]
run_console() {
  if [[ -n "$1" ]]; then
    echo "$1" >"$SCRATCH_HOME/.config/ohmydebn/current/default-ai"
  fi
  OUTPUT=$(HOME="$SCRATCH_HOME" SHELL="$MOCK_BIN/fake-shell" PATH="$(mock_path)" \
    MOCK_INSTALLED="$2" MOCK_AI_EXIT="${3:-0}" bash "$MOCK_DIR/console-run" </dev/null 2>&1)
  EXIT_CODE=$?
  CALLS=$(cat "$MOCK_CALLS")
}

package_of() {
  sed -n "/^package_of()/,/^}/p" "$REPO_ROOT/bin/ohmydebn-ai-set-default" |
    grep -oP "^\s*\Q$1\E\) echo \"\K[^\"]+"
}

# Each terminal assistant, installed: runs its -cli wrapper, then the shell.
for name in "${TERMINAL_AIS[@]}"; do
  setup
  run_console "$name" "$(package_of "$name")"
  assert_eq "$name installed: runs ohmydebn-$name-cli, then the shell" \
    "$(printf 'ran ohmydebn-%s-cli\nran the shell' "$name")" "$CALLS"
  assert_eq "$name installed: no note" "" "$OUTPUT"
  teardown
done

# Each terminal assistant, not installed: a note and the shell, no installer.
for name in "${TERMINAL_AIS[@]}"; do
  setup
  run_console "$name" ""
  assert_eq "$name not installed: only the shell runs (no -cli, no installer)" "ran the shell" "$CALLS"
  assert_contains "$name not installed: says so" "$OUTPUT" "($name) isn't installed"
  teardown
done

# Each desktop-app default, installed: a note naming it, and the shell.
for name in "${DESKTOP_AIS[@]}"; do
  setup
  run_console "$name" "$(package_of "$name")"
  assert_eq "$name: only the shell runs" "ran the shell" "$CALLS"
  assert_contains "$name: says it's a desktop app" "$OUTPUT" "is a desktop app, so this console opens a shell"
  teardown
done

setup
run_console "claude-desktop" "claude-desktop"
assert_contains "desktop app: named as Setup > Defaults shows it" "$OUTPUT" "Your default AI assistant, Claude Desktop, is a desktop app"
assert_contains "desktop app: says where to choose another" "$OUTPUT" "Setup > Defaults > Agent"
teardown

# No default chosen yet: OpenCode, as Super + A and the `a` alias assume.
setup
run_console "" "ohmydebn-opencode-cli"
assert_eq "no default set: OpenCode, then the shell" "$(printf 'ran ohmydebn-opencode-cli\nran the shell')" "$CALLS"
teardown

# The assistant failing or quitting with an error still leaves the shell.
setup
run_console "codex" "ohmydebn-codex-cli" 3
assert_eq "assistant exits with an error: the shell still opens" \
  "$(printf 'ran ohmydebn-codex-cli\nran the shell')" "$CALLS"
assert_eq "assistant exits with an error: the console doesn't fail" "0" "$EXIT_CODE"
teardown

# The list of terminal assistants here must match the ones with a -cli
# wrapper, so a new terminal assistant isn't silently treated as a desktop
# app.
CLI_NAMES=$(grep -oP '^\w[\w-]*(?=\) exec /usr/share/ohmydebn/bin/ohmydebn-[\w-]+-cli\b)' "$REPO_ROOT/bin/ohmydebn-ai-cli" | sort | tr '\n' ' ')
RUN_NAMES=$(grep -oP '^[a-z][a-z |-]*(?=\) terminal_ai=true)' "$REPO_ROOT/bin/ohmydebn-console-run" | tr -d ' ' | tr '|' '\n' | sort | tr '\n' ' ')
assert_eq "terminal assistants match ohmydebn-ai-cli's -cli wrappers" "$CLI_NAMES" "$RUN_NAMES"

python3 "$REPO_ROOT/tests/unit/test-console.py" || TESTS_FAILED=$((TESTS_FAILED + 1))

test_summary
