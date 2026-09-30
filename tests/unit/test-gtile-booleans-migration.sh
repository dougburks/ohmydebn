#!/bin/bash
#
# Unit tests for install/config/cinnamon.sh's one-time gTile settings fix.
# 4.8.0 and earlier seeded ~/.config/cinnamon/spices/gTile@OhMyDebn with
# five checkbox defaults/values stored as the strings "true"/"false"; gTile
# reads them raw, and in JavaScript "false" is truthy, so two settings acted
# as on while the dialog showed them off. The seed was fixed for new
# installs, and this converts existing users' files once: checkbox strings
# become booleans, nothing else changes, Cinnamon is flagged for a restart,
# and a failed conversion is retried on the next run. gsettings and the
# headline are mocked; HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/cinnamon.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/cinnamon.sh (gTile checkbox booleans) ==="

setup() {
  mock_init
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF
  mock_bin gsettings <<'EOF'
#!/bin/bash
exit 0
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/cinnamon-patched.sh"
  SCRATCH_HOME=$(mktemp -d)
  STATE="$SCRATCH_HOME/.local/state"
  SETTINGS_DIR="$SCRATCH_HOME/.config/cinnamon/spices/gTile@OhMyDebn"
  SETTINGS="$SETTINGS_DIR/gTile@OhMyDebn.json"
  MARKER="$STATE/ohmydebn-config/gtile-booleans-20260926"
  # Every earlier block's state file, so only the blocks after them run
  # (the earlier ones copy from /usr/share/ohmydebn, which isn't here).
  mkdir -p "$STATE/ohmydebn-config" "$SETTINGS_DIR"
  for f in ohmydebn-panel ohmydebn-panel-applet ohmydebn-window-speed ohmydebn-alttab ohmydebn-spices; do
    touch "$STATE/$f"
  done
  touch "$STATE/ohmydebn-config/gTile-config-20250920" "$STATE/ohmydebn-config/nemo-config-20250924"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# Sourced under set -e, as install.sh does (through ohmydebn.sh and
# install/config/all.sh): any unguarded failing command would end the
# install, and "run finished" is only printed if it didn't. The restart flag
# it sets is visible afterwards.
run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash -c \
    'set -e; source "$1" >/dev/null 2>&1; echo "run finished restart=${OHMYDEBN_CINNAMON_RESTART_NEEDED:-}"' _ "$MOCK_DIR/cinnamon-patched.sh" </dev/null
}

# The shape of a 4.8.0 settings file: checkbox strings (one of them next to
# a real boolean value, as the old seed had), a user's real-boolean choice,
# and non-checkbox settings that must not change even when their text is
# "true".
old_settings() {
  cat >"$SETTINGS" <<'EOF'
{
  "hotkey": { "type": "keybinding", "default": "<Ctrl><Shift>g", "value": "<Primary><Shift>g::" },
  "animation": { "type": "checkbox", "default": "true", "value": false },
  "useMonitorCenter": { "type": "checkbox", "default": "false", "value": "false" },
  "showGridOnAllMonitors": { "type": "checkbox", "default": "false", "value": "false" },
  "autoclose": { "type": "checkbox", "default": true, "value": true },
  "note": { "type": "entry", "default": "true", "value": "true" }
}
EOF
}

get() { jq -c ".\"$1\".$2" "$SETTINGS"; }

# --- a 4.8.0 file: checkbox strings become booleans, nothing else changes ---
setup
old_settings
OUT=$(run)
assert_eq "old file: string false -> false" "false" "$(get useMonitorCenter value)"
assert_eq "old file: second setting's value -> false" "false" "$(get showGridOnAllMonitors value)"
assert_eq "old file: string default true -> true" "true" "$(get animation default)"
assert_eq "old file: the value beside it stays the real boolean false" "false" "$(get animation value)"
assert_eq "old file: a real boolean stays" "true" "$(get autoclose value)"
assert_eq "old file: a non-checkbox \"true\" stays text" '"true"' "$(get note value)"
assert_eq "old file: the keybinding is untouched" '"<Primary><Shift>g::"' "$(get hotkey value)"
assert_eq "old file: no checkbox strings left" "0" "$(jq '[.[] | objects | select(.type == "checkbox") | .default, .value | strings] | length' "$SETTINGS")"
assert_eq "old file: still valid JSON" "0" "$(jq empty "$SETTINGS" >/dev/null 2>&1; echo $?)"
assert_contains "old file: announced" "$(cat "$MOCK_CALLS")" "Fixing gTile checkbox settings stored as text"
assert_eq "old file: Cinnamon flagged for a restart" "run finished restart=1" "$OUT"
assert_eq "old file: marked done" "yes" "$([[ -f "$MARKER" ]] && echo yes || echo no)"
teardown

# --- a file with real booleans already: left exactly as it is ---
setup
old_settings
jq '.useMonitorCenter.default = false | .useMonitorCenter.value = false | .showGridOnAllMonitors.default = false
  | .showGridOnAllMonitors.value = false | .animation.default = true' "$SETTINGS" >"$SETTINGS.new" && mv "$SETTINGS.new" "$SETTINGS"
BEFORE=$(cat "$SETTINGS")
OUT=$(run)
assert_eq "clean file: unchanged" "$BEFORE" "$(cat "$SETTINGS")"
assert_not_contains "clean file: nothing announced" "$(cat "$MOCK_CALLS")" "Fixing gTile"
assert_eq "clean file: no restart" "run finished restart=" "$OUT"
assert_eq "clean file: marked done" "yes" "$([[ -f "$MARKER" ]] && echo yes || echo no)"
teardown

# --- no gTile settings file at all: nothing to do ---
setup
OUT=$(run)
assert_eq "no file: the install carries on" "run finished restart=" "$OUT"
assert_eq "no file: none created" "no" "$([[ -e "$SETTINGS" ]] && echo yes || echo no)"
assert_eq "no file: marked done" "yes" "$([[ -f "$MARKER" ]] && echo yes || echo no)"
teardown

# --- the conversion fails: file untouched, retried on the next run ---
setup
old_settings
BEFORE=$(cat "$SETTINGS")
REAL_JQ=$(command -v jq)
mock_bin jq <<EOF
#!/bin/bash
[ "\$1" = "-e" ] && exec "$REAL_JQ" "\$@"
exit 5
EOF
OUT=$(run)
assert_eq "conversion fails: file untouched" "$BEFORE" "$(cat "$SETTINGS")"
assert_eq "conversion fails: no temporary file left" "no" "$([[ -e "$SETTINGS.tmp" ]] && echo yes || echo no)"
assert_eq "conversion fails: no restart" "run finished restart=" "$OUT"
assert_eq "conversion fails: not marked done, so it's retried" "no" "$([[ -f "$MARKER" ]] && echo yes || echo no)"
rm "$MOCK_BIN/jq"
run >/dev/null
assert_eq "conversion fails: the next run converts it" "false" "$(get useMonitorCenter value)"
teardown

# --- jq can't read the file at all (missing, or broken JSON): retried ---
setup
echo "{ not json" >"$SETTINGS"
OUT=$(run)
assert_eq "unreadable file: the install carries on" "run finished restart=" "$OUT"
assert_eq "unreadable file: left as it is" "{ not json" "$(cat "$SETTINGS")"
assert_eq "unreadable file: not marked done, so it's retried" "no" "$([[ -f "$MARKER" ]] && echo yes || echo no)"
teardown

# --- already done once: never touched again ---
setup
old_settings
touch "$MARKER"
BEFORE=$(cat "$SETTINGS")
run >/dev/null
assert_eq "marker present: file untouched" "$BEFORE" "$(cat "$SETTINGS")"
teardown

test_summary
