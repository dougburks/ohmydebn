#!/bin/bash
#
# Unit tests for bin/ohmydebn-claude-code-install's theming. The Claude Code
# theme hook does nothing while Claude Code isn't installed, so the
# installer themes it with the current OhMyDebn theme right after
# installing it - otherwise its first start would wait for the next theme
# switch. A theme that can't be applied mustn't fail the install. sudo,
# dpkg and the OhMyDebn commands it calls are stand-ins.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-claude-code-install: theme ==="

# setup <exit status of the theme hook>
setup() {
  mock_init
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 1
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
cat >/dev/null
STUB
  mock_bin ohmydebn-theme-set-claude <<STUB
#!/bin/bash
mock_log "theme-set-claude \$*"
exit $1
STUB
  mock_bin ohmydebn-ai-set-default <<'STUB'
#!/bin/bash
mock_log "ai-set-default $*"
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-claude-code-install" >"$MOCK_DIR/install"
}

run() {
  PATH="$(mock_path)" bash "$MOCK_DIR/install" --skip-prompt </dev/null >/dev/null 2>&1
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

setup 0
run
assert_eq "installs: exits 0" "0" "$STATUS"
assert_contains "installs Claude Code" "$CALLS" "sudo /usr/bin/apt -y install claude-code"
assert_contains "then themes it with the current theme" "$CALLS" "theme-set-claude --current"
assert_eq "themed after it's installed" "theme-set-claude --current" \
  "$(grep -A1 'apt -y install claude-code' "$MOCK_CALLS" | tail -1)"
mock_cleanup

setup 1
run
assert_eq "a theme that can't be applied doesn't fail the install" "0" "$STATUS"
mock_cleanup

test_summary
