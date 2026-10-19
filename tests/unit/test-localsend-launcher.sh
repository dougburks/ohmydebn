#!/bin/bash
#
# Unit tests for bin/ohmydebn-localsend, behind Ctrl+Super+L and the
# menu's Utility > LocalSend. It used to run
# /usr/share/localsend_app/localsend_app, which the LocalSend package no
# longer has (it installs to /opt/localsend_app and links
# /usr/bin/localsend_app), so it quietly did nothing.
#
# /usr/bin/localsend_app and /usr/share/ohmydebn/bin are patched to mock
# scripts that only log; dpkg answers from MOCK_INSTALLED.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-localsend"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-localsend ==="

setup() {
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  mock_bin localsend_app <<'EOF2'
#!/bin/bash
mock_log "localsend_app $*"
EOF2
  mock_bin ohmydebn-launch-floating-terminal-with-presentation <<'EOF2'
#!/bin/bash
mock_log "install terminal $*"
EOF2
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/bin/localsend_app#$MOCK_BIN/localsend_app#g" "$SCRIPT" >"$MOCK_DIR/patched.sh"
}

# --- installed: LocalSend starts, nothing is installed ---
setup
MOCK_INSTALLED="localsend" PATH="$(mock_path)" bash "$MOCK_DIR/patched.sh" </dev/null >/dev/null 2>&1
STATUS=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "installed: succeeds" "0" "$STATUS"
assert_contains "installed: starts LocalSend" "$CALLS" "localsend_app"
assert_not_contains "installed: no install terminal" "$CALLS" "install terminal"
mock_cleanup

# --- not installed (and the install cancelled): offers the install, starts nothing ---
setup
MOCK_INSTALLED="" PATH="$(mock_path)" bash "$MOCK_DIR/patched.sh" </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "not installed: offers the install" "$CALLS" "install terminal LocalSend"
assert_not_contains "not installed, install cancelled: nothing started" "$CALLS" "localsend_app"
mock_cleanup

# The app path is the link LocalSend's own package makes (its postinst:
# ln -s /opt/localsend_app/localsend_app /usr/bin/localsend_app).
assert_contains "runs the /usr/bin link the package creates" "$(cat "$SCRIPT")" "/usr/bin/localsend_app"
assert_not_contains "not the old /usr/share path" "$(grep -v '^#' "$SCRIPT")" "/usr/share/localsend_app"

test_summary
