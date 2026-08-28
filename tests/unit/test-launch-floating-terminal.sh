#!/bin/bash
#
# Unit tests for bin/ohmydebn-launch-floating-terminal-with-presentation and
# bin/ohmydebn-launch-floating-terminal - the two shared helpers every
# on-demand app script (ohmydebn-boxes, ohmydebn-virtmanager, etc.) and
# ohmydebn-menu's present_terminal() use to pop a floating install/run
# terminal. Both scripts used to take just a <command> and left Alacritty's
# window title at its default ("Alacritty" in the taskbar, no matter what
# was actually running) - they now require a <title> first argument that
# gets threaded through to ohmydebn-terminal's own --title. Covers the arg
# count change and that the title actually reaches ohmydebn-terminal, not
# each app script's own choice of title text (there are ~20 of those - see
# tests/consistency.sh's title-argument guard for that).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRESENTATION_SCRIPT="$REPO_ROOT/bin/ohmydebn-launch-floating-terminal-with-presentation"
PLAIN_SCRIPT="$REPO_ROOT/bin/ohmydebn-launch-floating-terminal"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-launch-floating-terminal-with-presentation / bin/ohmydebn-launch-floating-terminal ==="

# Both scripts hardcode /usr/share/ohmydebn/bin/ohmydebn-terminal (and the
# -with-presentation one also hardcodes ohmydebn-show-logo/-show-done),
# skipping PATH entirely - patch those to the mock dir, same technique
# used throughout this suite for this exact class of problem.
patched_script() {
  sed "s#/usr/share/ohmydebn/bin/#$MOCK_BIN/#g" "$1" >"$MOCK_DIR/patched.sh"
  echo "$MOCK_DIR/patched.sh"
}

setup_mocks() {
  mock_bin ohmydebn-terminal <<'EOF'
#!/bin/bash
echo "ohmydebn-terminal $*" >>"$MOCK_CALLS"
EOF
  mock_bin ohmydebn-show-logo <<'EOF'
#!/bin/bash
echo "ohmydebn-show-logo" >>"$MOCK_CALLS"
EOF
  mock_bin ohmydebn-show-done <<'EOF'
#!/bin/bash
echo "ohmydebn-show-done" >>"$MOCK_CALLS"
EOF
}

# --- ohmydebn-launch-floating-terminal-with-presentation ---

mock_init
setup_mocks
OUTPUT=$(PATH="$(mock_path)" bash "$PRESENTATION_SCRIPT" 2>&1)
EXIT_CODE=$?
assert_eq "with-presentation, no args: exits non-zero" "1" "$EXIT_CODE"
assert_contains "with-presentation, no args: usage mentions <title> <command>" "$OUTPUT" "Usage:"
assert_contains "with-presentation, no args: usage names <title>" "$OUTPUT" "<title>"
mock_cleanup

mock_init
setup_mocks
OUTPUT=$(PATH="$(mock_path)" bash "$PRESENTATION_SCRIPT" "only one arg" 2>&1)
EXIT_CODE=$?
assert_eq "with-presentation, one arg: exits non-zero" "1" "$EXIT_CODE"
assert_contains "with-presentation, one arg: usage error" "$OUTPUT" "Usage:"
mock_cleanup

mock_init
setup_mocks
PATH="$(mock_path)" bash "$(patched_script "$PRESENTATION_SCRIPT")" "Boxes" "echo installing" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "with-presentation: ohmydebn-terminal gets --title with the given title" "$CALLS" "--title Boxes"
assert_contains "with-presentation: still uses the OhMyDebn window class" "$CALLS" "--class OhMyDebn"
assert_contains "with-presentation: still wraps the command with the logo/done presentation" "$CALLS" "-e bash -c"
mock_cleanup

# --- ohmydebn-launch-floating-terminal (no logo/done wrapping - used for
# actually running an already-installed app, e.g. PowerShell/SO-CRATES) ---

mock_init
setup_mocks
OUTPUT=$(PATH="$(mock_path)" bash "$PLAIN_SCRIPT" 2>&1)
EXIT_CODE=$?
assert_eq "plain, no args: exits non-zero" "1" "$EXIT_CODE"
assert_contains "plain, no args: usage names <title>" "$OUTPUT" "<title>"
mock_cleanup

mock_init
setup_mocks
PATH="$(mock_path)" bash "$(patched_script "$PLAIN_SCRIPT")" "PowerShell" "/usr/bin/pwsh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "plain: ohmydebn-terminal gets --title with the given title" "$CALLS" "--title PowerShell"
assert_not_contains "plain: never runs the logo/done presentation" "$CALLS" "ohmydebn-show-logo"
mock_cleanup

test_summary
