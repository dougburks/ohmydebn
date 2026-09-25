#!/bin/bash
#
# Unit tests for OhMyDebn Menu > Update > Channel: bin/ohmydebn-channel
# (OhMyDebn stable/testing - the apt source's URIs line) and
# bin/ohmydebn-claude-code-channel (Claude Code stable/latest - the channel
# in claude-code.list), and bin/ohmydebn-menu's pickers for them. Testing
# must take a typed "testing" (a strong warning, where a reflexive y or
# Enter does nothing), latest a [y/N] that defaults to no, and moving back
# to stable must never downgrade. The /etc/apt files are sed-patched to
# scratch copies and sudo runs sed for real but only logs apt, so nothing
# here touches the real system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-channel / ohmydebn-claude-code-channel / Update > Channel ==="

STABLE_SOURCES='Types: deb
URIs: https://packages.ohmydebn.org/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/ohmydebn-keyring.gpg'
CLAUDE_LINE='deb [signed-by=/usr/share/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main'

# setup <claude-code installed: yes|no>
setup() {
  local claude_installed="$1"
  mock_init
  mock_bin dpkg <<EOF2
#!/bin/bash
[[ "\$1" == "-s" && "\$2" == "claude-code" && "$claude_installed" == "yes" ]] && exit 0
exit 1
EOF2
  # sed really edits the scratch files; apt is only logged.
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$1" == "sed" ]] && exec "$@"
exit 0
EOF2
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
echo "== $*"
EOF2
  SOURCES="$MOCK_DIR/ohmydebn.sources"
  CLAUDE_LIST="$MOCK_DIR/claude-code.list"
  echo "$STABLE_SOURCES" >"$SOURCES"
  echo "$CLAUDE_LINE" >"$CLAUDE_LIST"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/etc/apt/sources.list.d/ohmydebn.sources#$SOURCES#g" \
    "$REPO_ROOT/bin/ohmydebn-channel" >"$MOCK_BIN/ohmydebn-channel"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/etc/apt/sources.list.d/claude-code.list#$CLAUDE_LIST#g" \
    "$REPO_ROOT/bin/ohmydebn-claude-code-channel" >"$MOCK_BIN/ohmydebn-claude-code-channel"
  chmod +x "$MOCK_BIN/ohmydebn-channel" "$MOCK_BIN/ohmydebn-claude-code-channel"
}

run() {
  PATH="$(mock_path)" bash "$MOCK_BIN/$1" "${@:2}"
}

uris() { grep '^URIs:' "$SOURCES"; }

# --- OhMyDebn: --current reads the URIs line ---
setup no
assert_eq "ohmydebn --current: stable" "stable" "$(run ohmydebn-channel --current)"
sed -i 's|packages.ohmydebn.org|packages-testing.ohmydebn.org|' "$SOURCES"
assert_eq "ohmydebn --current: testing" "testing" "$(run ohmydebn-channel --current)"
rm "$SOURCES"
assert_eq "ohmydebn --current: no source file is unknown" "unknown" "$(run ohmydebn-channel --current)"
mock_cleanup

# --- OhMyDebn: testing needs the word "testing" typed; y or Enter cancels ---
for answer in "" y yes; do
  setup no
  OUT=$(printf '%s\n' "$answer" | run ohmydebn-channel testing 2>&1)
  assert_contains "testing, answer '$answer': shows the strong warning" "$OUT" "WARNING: the OhMyDebn testing channel can break your system"
  assert_contains "testing, answer '$answer': cancels" "$OUT" "Cancelled. You're still on the OhMyDebn stable channel."
  assert_eq "testing, answer '$answer': source unchanged" "URIs: https://packages.ohmydebn.org/" "$(uris)"
  assert_not_contains "testing, answer '$answer': no apt update" "$(cat "$MOCK_CALLS")" "apt update"
  mock_cleanup
done

setup no
OUT=$(printf 'testing\n' | run ohmydebn-channel testing 2>&1)
assert_eq "testing, typed 'testing': switches the source" "URIs: https://packages-testing.ohmydebn.org/" "$(uris)"
assert_eq "testing, typed 'testing': leaves the rest of the source alone" \
  "$(echo "$STABLE_SOURCES" | grep -v '^URIs:')" "$(grep -v '^URIs:' "$SOURCES")"
assert_contains "testing, typed 'testing': refreshes apt" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt update"
assert_not_contains "testing: installs nothing itself (Update > OhMyDebn does)" "$(cat "$MOCK_CALLS")" "install"
assert_contains "testing: says how to get the packages" "$OUT" "run OhMyDebn Menu > Update > OhMyDebn"

# --- OhMyDebn: back to stable takes a plain Enter, and says nothing is downgraded ---
: >"$MOCK_CALLS"
OUT=$(printf '\n' | run ohmydebn-channel stable 2>&1)
assert_eq "stable: switches the source back" "URIs: https://packages.ohmydebn.org/" "$(uris)"
assert_contains "stable: explains nothing is downgraded" "$OUT" "They aren't downgraded."
assert_not_contains "stable: no strong warning" "$OUT" "WARNING"
assert_contains "stable: refreshes apt" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt update"

# --- OhMyDebn: already on it, or a bad argument ---
: >"$MOCK_CALLS"
OUT=$(run ohmydebn-channel stable </dev/null 2>&1)
assert_contains "already stable: says so" "$OUT" "You're already on the OhMyDebn stable channel."
assert_eq "already stable: does nothing" "" "$(cat "$MOCK_CALLS")"
run ohmydebn-channel bogus >/dev/null 2>&1
assert_eq "bad argument: exits 1" "1" "$?"
mock_cleanup

# --- Claude Code: --current reads the deb line ---
setup yes
assert_eq "claude --current: stable" "stable" "$(run ohmydebn-claude-code-channel --current)"
mock_cleanup

# --- Claude Code: latest asks [y/N]; Enter or n cancels ---
for answer in "" n; do
  setup yes
  OUT=$(printf '%s\n' "$answer" | run ohmydebn-claude-code-channel latest 2>&1)
  assert_contains "latest, answer '$answer': shows the warning" "$OUT" "Warning: the Claude Code latest channel"
  assert_contains "latest, answer '$answer': cancels" "$OUT" "Cancelled. Claude Code is still on the stable channel."
  assert_eq "latest, answer '$answer': list unchanged" "$CLAUDE_LINE" "$(cat "$CLAUDE_LIST")"
  mock_cleanup
done

setup yes
OUT=$(printf 'y\n' | run ohmydebn-claude-code-channel latest 2>&1)
assert_eq "latest, 'y': switches both the path and the suite, keeps signed-by" \
  "deb [signed-by=/usr/share/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/latest latest main" \
  "$(cat "$CLAUDE_LIST")"
assert_contains "latest, 'y': refreshes apt" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt update"
assert_contains "latest, 'y': upgrades Claude Code right away" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y install --only-upgrade claude-code"
assert_eq "latest: --current now reports latest" "latest" "$(run ohmydebn-claude-code-channel --current)"

: >"$MOCK_CALLS"
OUT=$(printf '\n' | run ohmydebn-claude-code-channel stable 2>&1)
assert_eq "stable: switches back" "$CLAUDE_LINE" "$(cat "$CLAUDE_LIST")"
assert_contains "stable: explains it isn't downgraded" "$OUT" "It isn't downgraded."
assert_not_contains "stable: doesn't touch the installed version" "$(cat "$MOCK_CALLS")" "install"
mock_cleanup

# --- Claude Code: not installed ---
setup no
OUT=$(printf 'y\n' | run ohmydebn-claude-code-channel latest 2>&1)
assert_contains "claude not installed: points to Apps > AI" "$OUT" "Claude Code isn't installed. Install it first: OhMyDebn Menu > Apps > AI."
assert_eq "claude not installed: list unchanged" "$CLAUDE_LINE" "$(cat "$CLAUDE_LIST")"
mock_cleanup

# --- Update > Channel pickers ---
setup_picker() {
  local ohmydebn_current="$1" claude_current="$2" claude_installed="$3"
  mock_init
  mock_bin ohmydebn-channel <<EOF2
#!/bin/bash
echo "$ohmydebn_current"
EOF2
  mock_bin ohmydebn-claude-code-channel <<EOF2
#!/bin/bash
echo "$claude_current"
EOF2
  mock_bin dpkg <<EOF2
#!/bin/bash
[[ "$claude_installed" == "yes" ]]
EOF2
  mock_bin notify-send <<'EOF2'
#!/bin/bash
mock_log "notify $2"
EOF2
  sed -n '/^pick_ohmydebn_channel() {/,/^}/p;/^pick_claude_code_channel() {/,/^}/p' "$REPO_ROOT/bin/ohmydebn-menu" |
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" >"$MOCK_DIR/pickers.sh"
}

run_picker() {
  local func="$1" pick="$2"
  PATH="$(mock_path)" PICK="$pick" bash -c '
    source "$MOCK_DIR/pickers.sh"
    menu() { mock_log "items $2"; MENU_RESULT="$PICK"; }
    show_channel_menu() { mock_log "back"; }
    present_terminal() { mock_log "terminal $1 | $2"; }
    '"$func"
}

setup_picker stable latest yes
run_picker pick_ohmydebn_channel "Testing (unreleased)"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "ohmydebn picker: marks stable as current" "$CALLS" "Stable (recommended) (current)"
assert_not_contains "ohmydebn picker: testing isn't marked" "$CALLS" "Testing (unreleased) (current)"
assert_contains "ohmydebn picker: testing runs the switch in a terminal" "$CALLS" \
  "terminal OhMyDebn Channel | $MOCK_BIN/ohmydebn-channel testing"
mock_cleanup

setup_picker stable latest yes
run_picker pick_claude_code_channel "Stable (a week behind)"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "claude picker: marks latest as current" "$CALLS" "Latest (newest releases) (current)"
assert_contains "claude picker: stable runs the switch in a terminal" "$CALLS" \
  "terminal Claude Code Channel | $MOCK_BIN/ohmydebn-claude-code-channel stable"
mock_cleanup

setup_picker stable latest yes
run_picker pick_ohmydebn_channel ""
assert_contains "picker: Back returns to Channel" "$(cat "$MOCK_CALLS")" "back"
assert_not_contains "picker: Back switches nothing" "$(cat "$MOCK_CALLS")" "terminal"
mock_cleanup

setup_picker stable stable no
run_picker pick_claude_code_channel "Latest (newest releases)"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "claude picker, not installed: says so" "$CALLS" "notify Claude Code isn't installed. Install it from Apps > AI."
assert_not_contains "claude picker, not installed: shows no list" "$CALLS" "items"
mock_cleanup

test_summary
