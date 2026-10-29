#!/bin/bash
#
# Unit tests for OpenCode following the OhMyDebn theme: install/config/
# opencode.sh sets OpenCode's "system" theme (the terminal's colors), and
# bin/ohmydebn-theme-set-opencode has the terminal app reload it.
#
# OpenCode 2 reads its theme from cli.json, not opencode.json where
# OhMyDebn set it, so it showed OpenCode's own theme whatever the OhMyDebn
# theme was. Before OpenCode 2's first run the theme goes in OpenCode 1's
# tui.json, which OpenCode 2 carries into cli.json with the user's other
# settings; a theme the user chose is never replaced.
#
# The theme switch used to signal every opencode-cli, and the signal ends
# OpenCode's servers, which run under the same name (checked with 2.2.1's
# opencode-cli serve). pgrep and ps are mocked, describing the processes;
# kill is a logging function, exported to the hook.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/opencode.sh, bin/ohmydebn-theme-set-opencode ==="

setup() {
  mock_init
  printf '#!/bin/bash\nmock_log "headline $*"\n' | mock_bin ohmydebn-headline
  SCRATCH_HOME=$(mktemp -d)
  CLI="$SCRATCH_HOME/.config/opencode/cli.json"
  TUI="$SCRATCH_HOME/.config/opencode/tui.json"
  KV="$SCRATCH_HOME/.local/state/opencode/kv.json"
  MARKER="$SCRATCH_HOME/.local/state/ohmydebn-config/opencode-system-theme-20261029"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" \
    "$REPO_ROOT/install/config/opencode.sh" >"$MOCK_DIR/opencode-patched.sh"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# An existing user's OpenCode folder (the first-install copy is skipped).
existing_user() {
  mkdir -p "$SCRATCH_HOME/.config/opencode" "$SCRATCH_HOME/.local/state/opencode"
  printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "theme": "system"\n}\n' \
    >"$SCRATCH_HOME/.config/opencode/opencode.json"
}

# Sourced under set -e, as the install does.
run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash -c 'set -e; source "$1"; echo "run finished"' _ "$MOCK_DIR/opencode-patched.sh" </dev/null >"$MOCK_DIR/out" 2>&1
  assert_contains "the install carries on past opencode.sh" "$(cat "$MOCK_DIR/out")" "run finished"
}

# --- a new install: OhMyDebn's config, with the theme in cli.json ---
setup
run
assert_eq "new install: cli.json sets the system theme" "system" "$(jq -r '.theme.name' "$CLI")"
assert_eq "new install: opencode.json no longer sets a theme" "null" \
  "$(jq -r '.theme' "$SCRATCH_HOME/.config/opencode/opencode.json")"
assert_eq "new install: no tui.json" "no" "$([ -e "$TUI" ] && echo yes || echo no)"
assert_eq "new install: marker set" "yes" "$([ -f "$MARKER" ] && echo yes || echo no)"
teardown

# --- OpenCode 2 has run: its cli.json gets the theme, keeping the rest ---
setup
existing_user
printf '{\n  "$schema": "https://opencode.ai/v2/cli.json",\n  "theme": {"mode": "dark"},\n  "scroll": {"speed": 3}\n}\n' >"$CLI"
run
assert_eq "cli.json without a theme name: system added" "system" "$(jq -r '.theme.name' "$CLI")"
assert_eq "cli.json: its color mode kept" "dark" "$(jq -r '.theme.mode' "$CLI")"
assert_eq "cli.json: other settings kept" "3" "$(jq -r '.scroll.speed' "$CLI")"
assert_eq "cli.json: no tui.json written" "no" "$([ -e "$TUI" ] && echo yes || echo no)"
assert_eq "cli.json: no temporary file left" "" "$(find "$SCRATCH_HOME/.config/opencode" -name 'cli.json.*')"
teardown

setup
existing_user
echo '{"theme": {"name": "nord"}}' >"$CLI"
run
assert_eq "a theme the user chose in cli.json: kept" '{"theme": {"name": "nord"}}' "$(cat "$CLI")"
teardown

setup
existing_user
printf '{\n  // mine\n  "scroll": {"speed": 3}\n}\n' >"$CLI"
BEFORE=$(cat "$CLI")
run
assert_eq "a cli.json jq can't read (comments): left alone" "$BEFORE" "$(cat "$CLI")"
assert_eq "unreadable cli.json: marker still set" "yes" "$([ -f "$MARKER" ] && echo yes || echo no)"
teardown

# --- before OpenCode 2's first run: the theme goes in tui.json ---
setup
existing_user
run
assert_eq "no cli.json yet: tui.json sets the system theme" "system" "$(jq -r '.theme' "$TUI")"
assert_eq "no cli.json yet: OpenCode 1's tui.json schema" "https://opencode.ai/tui.json" "$(jq -r '."$schema"' "$TUI")"
assert_eq "no cli.json yet: cli.json left for OpenCode to make" "no" "$([ -e "$CLI" ] && echo yes || echo no)"
teardown

setup
existing_user
echo '{"scroll_speed": 3}' >"$TUI"
run
assert_eq "tui.json without a theme: system added" "system" "$(jq -r '.theme' "$TUI")"
assert_eq "tui.json: other settings kept" "3" "$(jq -r '.scroll_speed' "$TUI")"
teardown

setup
existing_user
echo '{"theme": "gruvbox"}' >"$TUI"
run
assert_eq "a theme the user set in tui.json: kept" '{"theme": "gruvbox"}' "$(cat "$TUI")"
teardown

setup
existing_user
echo '{"theme": "nord", "thinking_visibility": true}' >"$KV"
run
assert_eq "a theme picked with /themes in OpenCode 1: no tui.json to override it" "no" \
  "$([ -e "$TUI" ] && echo yes || echo no)"
teardown

# --- only once: a theme the user later removes isn't put back ---
setup
existing_user
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
echo '{"scroll": {"speed": 3}}' >"$CLI"
run
assert_eq "marker set: cli.json not touched" '{"scroll": {"speed": 3}}' "$(cat "$CLI")"
teardown

# --- the theme switch signals only OpenCode's terminal app ---
mock_init
# pgrep -x opencode-cli lists every PID below; ps describes each as
# "<tty> <args>", the way ps -o tty=,args= does.
cat >"$MOCK_DIR/procs" <<'EOF2'
101 pts/0 /usr/bin/opencode-cli
102 pts/0 /usr/bin/opencode-cli serve --service
103 ? /usr/bin/opencode-cli serve --port 0
104 ? /opt/OpenCode/resources/opencode-cli serve --service
105 pts/1 /usr/bin/opencode-cli --continue /home/user/serve-notes
106 pts/2 /usr/bin/opencode-cli run fix the tests
107 pts/2 /usr/bin/opencode-cli auth login
108 ? /usr/bin/opencode-cli
109 pts/3 /usr/bin/opencode-cli acp
EOF2
mock_bin pgrep <<'EOF2'
#!/bin/bash
[[ "$*" == "-x opencode-cli" ]] && cut -d' ' -f1 "$MOCK_DIR/procs"
EOF2
mock_bin ps <<'EOF2'
#!/bin/bash
[[ "$1 $2" == "-o tty=,args=" && "$3" == "-p" ]] || exit 1
grep "^$4 " "$MOCK_DIR/procs" | cut -d' ' -f2-
EOF2
kill() { mock_log "kill $*"; }
export -f kill
PATH="$(mock_path)" bash "$REPO_ROOT/bin/ohmydebn-theme-set-opencode" </dev/null
STATUS=$?
unset -f kill
assert_eq "theme switch: exits 0" "0" "$STATUS"
assert_eq "theme switch: only the terminal app, including its run command" "kill -USR2 101
kill -USR2 105
kill -USR2 106" "$(cat "$MOCK_CALLS")"
mock_cleanup

mock_init
printf '#!/bin/bash\nexit 1\n' | mock_bin pgrep
PATH="$(mock_path)" bash "$REPO_ROOT/bin/ohmydebn-theme-set-opencode" </dev/null
assert_eq "theme switch, OpenCode not running: exits 0" "0" "$?"
mock_cleanup

test_summary
