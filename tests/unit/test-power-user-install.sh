#!/bin/bash
#
# Unit tests for bin/ohmydebn-power-user-install - the post-install,
# user-facing wrapper around install/packaging/power-user.sh. Confirms it
# prompts before doing anything (Ctrl-C/EOF at the prompt must never reach
# power-user.sh), and that a confirmed run invokes power-user.sh with
# POWER_USER=true exported (the only thing power-user.sh actually needs from
# its caller - see the comment in that file).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-power-user-install"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-power-user-install ==="

# The script invokes power-user.sh by its hardcoded /usr/share/ohmydebn
# path, which skips PATH entirely - patch that path to a mock script, same
# technique test-power-user-flow.sh and test-virtmanager-install.sh use for
# this exact class of problem.
patched_script() {
  sed "s#/usr/share/ohmydebn/install/packaging/power-user.sh#$MOCK_DIR/power-user.sh#" \
    "$SCRIPT" >"$MOCK_DIR/power-user-install-patched.sh"
  echo "$MOCK_DIR/power-user-install-patched.sh"
}

# Scenario 1: confirmed at the prompt -> power-user.sh runs with
# POWER_USER=true exported.
mock_init
cat >"$MOCK_DIR/power-user.sh" <<'EOF'
#!/bin/bash
echo "power-user.sh POWER_USER=$POWER_USER" >>"$MOCK_CALLS"
EOF
chmod +x "$MOCK_DIR/power-user.sh"
bash "$(patched_script)" <<<"" >/dev/null 2>&1
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "confirmed: exits cleanly" "0" "$EXIT_CODE"
assert_contains "confirmed: power-user.sh runs with POWER_USER=true" "$CALLS" "power-user.sh POWER_USER=true"
mock_cleanup

# Scenario 2: EOF at the prompt (Ctrl-C/closed stdin) -> `read -r` fails,
# `set -e` bails before power-user.sh is ever reached.
mock_init
cat >"$MOCK_DIR/power-user.sh" <<'EOF'
#!/bin/bash
echo "power-user.sh POWER_USER=$POWER_USER" >>"$MOCK_CALLS"
EOF
chmod +x "$MOCK_DIR/power-user.sh"
bash "$(patched_script)" </dev/null >/dev/null 2>&1
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "cancelled: exits non-zero" "1" "$EXIT_CODE"
assert_eq "cancelled: power-user.sh never runs" "" "$CALLS"
mock_cleanup

test_summary
