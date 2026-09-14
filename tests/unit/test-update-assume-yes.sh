#!/bin/bash
#
# Unit tests for bin/ohmydebn-update's --yes flag, which
# ohmydebn-update-gui passes when it runs the update inside its embedded
# terminal: the GUI's "Update Now" button IS the confirmation, so with
# --yes the script must not block on a "Press Enter" stdin read. --yes
# must NOT be forwarded to install.sh, though: its prompts are separate
# consents (unsupported-distro/root warnings) the button never covered -
# the GUI surfaces those in its terminal instead (see
# CONSENT_PROMPT_MARKER in bin/ohmydebn-update-gui). Without --yes, the
# interactive terminal flow must be unchanged.
#
# SAFETY: dpkg is mocked to report ohmydebn NOT installed, which routes
# the script to $HOME/.local/share/ohmydebn - a scratch tree built here -
# and also skips the "sudo apt install ohmydebn" self-update branch
# entirely. sudo is mocked as a pure logger, so nothing touches the real
# system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-update"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-update: --yes ==="

mock_init

mock_bin dpkg <<'EOF'
#!/bin/bash
exit 1
EOF
mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF

# Scratch ~/.local/share/ohmydebn tree with just enough for the script:
# a version reporter, a headline printer, and an install.sh that logs how
# it was invoked instead of installing anything.
FAKE_HOME="$MOCK_DIR/home"
FAKE_TREE="$FAKE_HOME/.local/share/ohmydebn"
mkdir -p "$FAKE_TREE/bin"
cat >"$FAKE_TREE/bin/ohmydebn-version" <<'EOF'
#!/bin/bash
echo 1.2.3
EOF
cat >"$FAKE_TREE/bin/ohmydebn-headline" <<'EOF'
#!/bin/bash
echo "HEADLINE: $1"
EOF
cat >"$FAKE_TREE/install.sh" <<'EOF'
#!/bin/bash
mock_log "install.sh $*"
EOF
chmod +x "$FAKE_TREE"/bin/* "$FAKE_TREE/install.sh"

# --yes with stdin closed: must complete without hanging or reading, and
# must hand --yes to install.sh.
OUTPUT=$(HOME="$FAKE_HOME" PATH="$(mock_path)" bash "$SCRIPT" --yes </dev/null 2>&1)
STATUS=$?
assert_eq "--yes run exits 0 with stdin closed" "0" "$STATUS"
assert_not_contains "--yes skips the Press Enter prompt" "$OUTPUT" "Press Enter"
assert_contains "--yes still prints the version headline" "$OUTPUT" "current OhMyDebn version: 1.2.3"
assert_contains "install.sh is invoked" "$(cat "$MOCK_CALLS")" "install.sh"
assert_not_contains "--yes is NOT forwarded to install.sh (its distro/root consent prompts must survive)" "$(cat "$MOCK_CALLS")" "install.sh --yes"
assert_contains "time sync still runs under --yes" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/chronyc makestep"

# Without --yes: the interactive prompt still appears and install.sh is
# invoked without the flag (a newline on stdin stands in for the user's
# Enter).
: >"$MOCK_CALLS"
OUTPUT=$(HOME="$FAKE_HOME" PATH="$(mock_path)" bash "$SCRIPT" <<<"" 2>&1)
STATUS=$?
assert_eq "interactive run exits 0" "0" "$STATUS"
assert_contains "interactive run keeps the Press Enter prompt" "$OUTPUT" "Press Enter to continue"
assert_contains "interactive run invokes install.sh" "$(cat "$MOCK_CALLS")" "install.sh"
assert_not_contains "interactive run does not pass --yes" "$(cat "$MOCK_CALLS")" "install.sh --yes"

mock_cleanup
test_summary
