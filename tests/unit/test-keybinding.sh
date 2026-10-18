#!/bin/bash
#
# Unit tests for install/keybinding/keybinding.sh - the stock keybinding
# pass. Covers what the pass writes and in what order, not the content of
# every binding (gsettings is a logging stub that accepts anything).
#
# Two properties matter most here:
#   - It must NOT schedule a Cinnamon restart. It used to set
#     OHMYDEBN_CINNAMON_RESTART_NEEDED (finalization/finale.sh does the one
#     restart), because Cinnamon only re-reads custom shortcuts when
#     custom-list itself changes and the list was written before the slots.
#     Now the list is written after the slots, twice (with Cinnamon
#     Settings' transient "__dummy__" appended, then without), so Cinnamon
#     reloads live - the same trick Cinnamon Settings uses.
#   - It must keep custom-list entries that aren't its own (GUI-added
#     shortcuts, the custom-1000+ user slots) instead of truncating.
#
# The script is sourced (not exec'd), matching finalization/keybinding.sh,
# so the restart variable can be observed the way finale.sh would see it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/keybinding/keybinding.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

# Read straight from the script rather than hardcoding the date-stamped
# marker name here too - keybinding.sh's KEYBINDING_STATE gets bumped every
# time a keybinding changes, and a second hardcoded copy here would silently
# fall out of sync.
KEYBINDING_MARKER=$(grep -oP '(?<=KEYBINDING_STATE=\$STATE_DIR/)\S+' "$SCRIPT")
STOCK_COUNT=$(grep -c '^keybinding-custom' "$REPO_ROOT/install/keybinding/keybinding-custom.txt")

echo "=== install/keybinding/keybinding.sh ==="

setup_mocks() {
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF
  # MOCK_CUSTOM_LIST, when set, is what `gsettings get ... custom-list`
  # returns - the union scenario uses it.
  mock_bin gsettings <<'EOF'
#!/bin/bash
mock_log "gsettings $*"
if [[ "$1 $2 $3" == "get org.cinnamon.desktop.keybindings custom-list" ]]; then
  echo "${MOCK_CUSTOM_LIST:-}"
fi
# MOCK_SLOT_NAME/COMMAND: what stock slot custom-$MOCK_SLOT holds now.
if [[ "$1" == get && -n "${MOCK_SLOT:-}" && "$2" == *custom-keybindings/custom-$MOCK_SLOT/ ]]; then
  case "$3" in
  name) echo "${MOCK_SLOT_NAME:-}" ;;
  command) echo "${MOCK_SLOT_COMMAND:-}" ;;
  esac
fi
exit 0
EOF
  mock_bin pgrep <<'EOF'
#!/bin/bash
mock_log "pgrep $*"
if [[ "${MOCK_CINNAMON_RUNNING:-true}" == "true" ]]; then
  echo "12345"
  exit 0
fi
exit 1
EOF
  # The user's own keybindings layer, run as a separate process after the
  # stock pass (and on every run, gated inside itself) - see keybinding.sh.
  mock_bin ohmydebn-keybindings-apply <<'EOF'
#!/bin/bash
mock_log "ohmydebn-keybindings-apply $* stock_applied=${OHMYDEBN_KEYBINDINGS_STOCK_APPLIED:-}"
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn/install/keybinding#$REPO_ROOT/install/keybinding#g" "$SCRIPT" >"$MOCK_DIR/keybinding-patched.sh"
}

# Sources the patched script and captures OHMYDEBN_CINNAMON_RESTART_NEEDED
# as finale.sh would see it. The variable is cleared going in - on a real
# OhMyDebn session it's commonly already exported to 1.
run_script() {
  RESTART_FLAG=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" OHMYDEBN_CINNAMON_RESTART_NEEDED='' bash -c "
    source '$MOCK_DIR/keybinding-patched.sh' >/dev/null 2>&1
    echo \"\${OHMYDEBN_CINNAMON_RESTART_NEEDED:-}\"
  ")
}

# --- first run (no state marker), Cinnamon running ---
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
MOCK_CINNAMON_RUNNING=true run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "first run: no Cinnamon restart scheduled" "" "$RESTART_FLAG"
assert_contains "first run: headline shown" "$CALLS" "ohmydebn-headline Updating keybindings"
assert_not_contains "first run: no 'will restart' headline" "$CALLS" "will restart"
assert_eq "first run: state marker written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER" ] && echo yes || echo no)"
assert_contains "first run: user keybindings applied afterwards, told the stock pass ran" "$CALLS" "ohmydebn-keybindings-apply --from-install stock_applied=1"
# Order and shape of the custom-list writes: after every slot write, first
# with __dummy__, then the final list.
LIST_SETS=$(grep -n 'gsettings set org.cinnamon.desktop.keybindings custom-list' "$MOCK_CALLS")
LAST_SLOT_SET=$(grep -n 'gsettings set .*custom-keybindings/custom-' "$MOCK_CALLS" | tail -1 | cut -d: -f1)
FIRST_LIST_SET=$(echo "$LIST_SETS" | head -1 | cut -d: -f1)
assert_eq "first run: custom-list written exactly twice" "2" "$(echo "$LIST_SETS" | wc -l)"
assert_eq "first run: custom-list written after the last slot" "yes" "$([ "$FIRST_LIST_SET" -gt "$LAST_SLOT_SET" ] && echo yes || echo no)"
assert_contains "first run: first list write carries __dummy__ so Cinnamon sees a change" "$(echo "$LIST_SETS" | head -1)" "'custom-$((STOCK_COUNT - 1))', '__dummy__']"
FINAL_LIST=$(echo "$LIST_SETS" | tail -1)
assert_not_contains "first run: final list has no __dummy__" "$FINAL_LIST" "__dummy__"
assert_contains "first run: final list ends with the last stock slot" "$FINAL_LIST" "'custom-$((STOCK_COUNT - 1))']"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- first run, Cinnamon NOT running: same writes, marker still written ---
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
MOCK_CINNAMON_RUNNING=false run_script
assert_eq "Cinnamon not running: no restart flag" "" "$RESTART_FLAG"
assert_eq "Cinnamon not running: state marker still written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER" ] && echo yes || echo no)"
assert_eq "Cinnamon not running: custom-list still written twice" "2" "$(grep -c 'gsettings set org.cinnamon.desktop.keybindings custom-list' "$MOCK_CALLS")"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- already run (state marker pre-seeded): nothing but the user layer ---
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER"
MOCK_CINNAMON_RUNNING=true run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "already run: no restart flag" "" "$RESTART_FLAG"
assert_not_contains "already run: no headline shown" "$CALLS" "ohmydebn-headline"
assert_not_contains "already run: no gsettings writes" "$CALLS" "gsettings set"
assert_contains "already run: user keybindings layer still consulted (it gates itself on the file's hash)" "$CALLS" "ohmydebn-keybindings-apply --from-install stock_applied="
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- custom-list keeps what isn't the stock pass's own ---
# Shortcuts added in Cinnamon Settings (custom5) and the user-keybindings
# slots (custom-1000) survive; Cinnamon Settings' transient __dummy__ from
# the old value is dropped; a stock slot already in the old list isn't
# listed twice.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
MOCK_CUSTOM_LIST="['custom-0', 'custom-1', 'custom5', 'custom-1000', '__dummy__']" MOCK_CINNAMON_RUNNING=true run_script
FINAL_LIST=$(grep 'gsettings set org.cinnamon.desktop.keybindings custom-list' "$MOCK_CALLS" | tail -1)
assert_contains "custom-list: stock slots present" "$FINAL_LIST" "'custom-0', 'custom-1', 'custom-2'"
assert_contains "custom-list: last stock slot present" "$FINAL_LIST" "'custom-$((STOCK_COUNT - 1))'"
assert_contains "custom-list: GUI-added shortcut kept" "$FINAL_LIST" "'custom5'"
assert_contains "custom-list: user keybinding slot kept" "$FINAL_LIST" "'custom-1000'"
assert_not_contains "custom-list: old __dummy__ dropped from the final list" "$FINAL_LIST" "__dummy__"
assert_eq "custom-list: stock slot listed once, not duplicated from the old list" "1" "$(grep -o "'custom-1'" <<<"$FINAL_LIST" | wc -l)"
assert_eq "custom-list: closes the array" "]" "${FINAL_LIST: -1}"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- Stock keybindings renamed without a new marker (Super + K's
# "Hotkeys" before 4.9.0, "GMail" and "Cloudflare Warp" before 4.11.0), so
# the new names never reached existing installs. Each is renamed in place
# on any run, marker or not - but only while the slot still runs what
# OhMyDebn put there.
# slot|old name|new name|the command OhMyDebn gave it
while IFS='|' read -r slot old new cmd; do
  slot_path="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$slot/"
  for case in "'$old'|$cmd|renamed" "'$new'|$cmd|kept" "'$old'|'my-own-script'|kept"; do
    IFS='|' read -r name command expect <<<"$case"
    mock_init
    setup_mocks
    SCRATCH_HOME=$(mktemp -d)
    mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
    touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER"
    MOCK_SLOT="$slot" MOCK_SLOT_NAME="$name" MOCK_SLOT_COMMAND="$command" MOCK_CINNAMON_RUNNING=true run_script
    CALLS=$(cat "$MOCK_CALLS")
    if [[ "$expect" == renamed ]]; then
      assert_contains "custom-$slot named $name, as OhMyDebn set it: renamed to $new" "$CALLS" "gsettings set $slot_path name $new"
      assert_eq "...and nothing else rewritten" "1" "$(grep -c 'gsettings set' "$MOCK_CALLS")"
    else
      assert_not_contains "custom-$slot named $name running $command: left as it is" "$CALLS" "gsettings set"
    fi
    rm -rf "$SCRATCH_HOME"
    mock_cleanup
  done
done <<'LIST'
4|Hotkeys|Keybindings|'/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://ohmydebn.org/hotkeys/'
2|GMail|Gmail|'/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://mail.google.com'
43|Cloudflare Warp|Cloudflare WARP|'/usr/share/ohmydebn/bin/ohmydebn-cloudflare-warp'
LIST

test_summary
