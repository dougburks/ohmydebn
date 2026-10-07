#!/bin/bash
#
# Unit tests for the install-if-needed-then-run payloads (the AI tools'
# and cliamp's -run, and ohmydebn-socrates-launch). They run in a terminal
# opened just for them, under set -e, so a failed install - no network on
# the first Super+A, say - used to end the script and close the terminal
# before the error could be read. Now a failed install says so and waits
# for Enter (ohmydebn-show-done) before exiting non-zero.
#
# dpkg reports nothing installed, the installer fails, and every
# /usr/share/ohmydebn/bin helper is a mock, so nothing touches the system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== -run payloads: a failed install stays on screen ==="

# <payload script> <installer it runs>
while read -r PAYLOAD INSTALLER; do
  mock_init
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 1
STUB
  mock_bin ohmydebn-podman-installed <<'STUB'
#!/bin/bash
exit 1
STUB
  mock_bin ohmydebn-show-logo <<'STUB'
#!/bin/bash
exit 0
STUB
  mock_bin ohmydebn-show-done <<'STUB'
#!/bin/bash
mock_log "show-done"
STUB
  mock_bin "$INSTALLER" <<'STUB'
#!/bin/bash
mock_log "install"
exit 100
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/$PAYLOAD" >"$MOCK_DIR/payload"
  OUTPUT=$(HOME="$MOCK_DIR" PATH="$(mock_path)" bash "$MOCK_DIR/payload" </dev/null 2>&1)
  STATUS=$?
  assert_eq "$PAYLOAD: exits non-zero" "1" "$STATUS"
  assert_contains "$PAYLOAD: says the install didn't finish" "$OUTPUT" "The install didn't finish"
  assert_eq "$PAYLOAD: waits for Enter after the failed install" "install
show-done" "$(cat "$MOCK_CALLS")"
  mock_cleanup
done <<'LIST'
ohmydebn-claude-code-run ohmydebn-claude-code-install
ohmydebn-codex-run ohmydebn-codex-install
ohmydebn-grok-run ohmydebn-grok-install
ohmydebn-omp-run ohmydebn-omp-install
ohmydebn-opencode-run ohmydebn-opencode-install
ohmydebn-pi-run ohmydebn-pi-install
ohmydebn-cliamp-run ohmydebn-cliamp-install
ohmydebn-socrates-launch ohmydebn-podman-install
LIST

test_summary
