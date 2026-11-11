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
# The highest stock slot: slot numbers aren't contiguous once a stock
# hotkey is removed (34, Antigravity, in 4.15.0).
LAST_STOCK_SLOT=$(awk '$1 == "keybinding-custom" {print $2}' "$REPO_ROOT/install/keybinding/keybinding-custom.txt" | sort -n | tail -1)

echo "=== install/keybinding/keybinding.sh ==="

setup_mocks() {
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF
  # MOCK_CUSTOM_LIST, when set, is what `gsettings get ... custom-list`
  # returns - the union scenario uses it - until the script writes the
  # list, after which it reads back what it wrote, as it would for real.
  mock_bin gsettings <<'EOF'
#!/bin/bash
mock_log "gsettings $*"
if [[ "$1 $2 $3" == "set org.cinnamon.desktop.keybindings custom-list" ]]; then
  echo "$4" >"$MOCK_DIR/custom-list"
fi
if [[ "$1 $2 $3" == "get org.cinnamon.desktop.keybindings custom-list" ]]; then
  if [[ -f "$MOCK_DIR/custom-list" ]]; then
    cat "$MOCK_DIR/custom-list"
  else
    echo "${MOCK_CUSTOM_LIST:-}"
  fi
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
assert_contains "first run: first list write carries __dummy__ so Cinnamon sees a change" "$(echo "$LIST_SETS" | head -1)" "'custom-$LAST_STOCK_SLOT', '__dummy__']"
FINAL_LIST=$(echo "$LIST_SETS" | tail -1)
assert_not_contains "first run: final list has no __dummy__" "$FINAL_LIST" "__dummy__"
assert_contains "first run: final list ends with the last stock slot" "$FINAL_LIST" "'custom-$LAST_STOCK_SLOT']"
# A removed stock hotkey leaves a gap: the list follows the file's own
# slot numbers, not a count of its lines (which listed custom-34, unset,
# and left out custom-48).
assert_contains "first run: the slots either side of removed slot 34 listed" "$FINAL_LIST" "'custom-33', 'custom-35'"
assert_not_contains "first run: removed slot 34 not listed" "$FINAL_LIST" "'custom-34'"
assert_not_contains "first run: removed slot 34 not written" "$(cat "$MOCK_CALLS")" "custom-keybindings/custom-34/"
assert_eq "first run: every stock slot in the file listed" \
  "$(awk '$1 == "keybinding-custom" {printf "'"'"'custom-%s'"'"', ", $2}' "$REPO_ROOT/install/keybinding/keybinding-custom.txt" | sed 's/, $//')" \
  "$(grep -oP "(?<=custom-list \[).*(?=\])" <<<"$FINAL_LIST")"
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
MOCK_CUSTOM_LIST="['custom-0', 'custom-1', 'custom-34', 'custom5', 'custom-1000', '__dummy__']" MOCK_CINNAMON_RUNNING=true run_script
FINAL_LIST=$(grep 'gsettings set org.cinnamon.desktop.keybindings custom-list' "$MOCK_CALLS" | tail -1)
assert_contains "custom-list: stock slots present" "$FINAL_LIST" "'custom-0', 'custom-1', 'custom-2'"
assert_contains "custom-list: last stock slot present" "$FINAL_LIST" "'custom-$LAST_STOCK_SLOT'"
assert_contains "custom-list: GUI-added shortcut kept" "$FINAL_LIST" "'custom5'"
assert_contains "custom-list: user keybinding slot kept" "$FINAL_LIST" "'custom-1000'"
assert_not_contains "custom-list: old __dummy__ dropped from the final list" "$FINAL_LIST" "__dummy__"
assert_eq "custom-list: stock slot listed once, not duplicated from the old list" "1" "$(grep -o "'custom-1'" <<<"$FINAL_LIST" | wc -l)"
assert_eq "custom-list: closes the array" "]" "${FINAL_LIST: -1}"
assert_not_contains "custom-list: a removed stock slot in the old list is dropped" "$FINAL_LIST" "'custom-34'"
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
      assert_eq "...and no other name rewritten" "1" "$(grep -c 'gsettings set .* name ' "$MOCK_CALLS")"
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

# --- Stock keybindings whose command changed since the marker: Super + K
# (custom-4) opened the docs' page in a browser, and lists the hotkeys
# itself (ohmydebn-hotkeys) since 4.17.0. Switched only while the slot still
# opens that page, and custom-list toggled through "__dummy__" so Cinnamon
# picks the new command up without a restart.
HOTKEYS_SLOT="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-4/"
# The list has Console (custom-48), so its own add-once step writes nothing.
# The script's /usr/share/ohmydebn/bin is the mock bin here (see
# setup_mocks), so the new command reads as "$MOCK_BIN/ohmydebn-hotkeys".
# run_retarget <slot 4's command now> [custom-list]
run_retarget() {
  mock_init
  setup_mocks
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER"
  MOCK_SLOT=4 MOCK_SLOT_NAME="'Keybindings'" MOCK_SLOT_COMMAND="$1" MOCK_CUSTOM_LIST="${2-['custom-0', 'custom-4', 'custom-48', 'custom-1000']}" \
    MOCK_CINNAMON_RUNNING=true run_script
  CALLS=$(cat "$MOCK_CALLS")
  LIST_SETS=$(grep 'gsettings set org.cinnamon.desktop.keybindings custom-list' "$MOCK_CALLS")
}

run_retarget "'/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://ohmydebn.org/hotkeys/'"
assert_contains "Super + K opening the docs' page: now opens the hotkey list" "$CALLS" \
  "gsettings set $HOTKEYS_SLOT command $MOCK_BIN/ohmydebn-hotkeys"
assert_contains "...and custom-list toggled through __dummy__ so Cinnamon reloads" "$(echo "$LIST_SETS" | head -1)" \
  "['custom-0', 'custom-4', 'custom-48', 'custom-1000', '__dummy__']"
assert_contains "...and put back as it was" "$(echo "$LIST_SETS" | tail -1)" "custom-list ['custom-0', 'custom-4', 'custom-48', 'custom-1000']"
assert_eq "...and no other slot touched" "1" "$(grep -c 'gsettings set .*custom-keybindings/' "$MOCK_CALLS")"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_retarget "'/usr/share/ohmydebn/bin/ohmydebn-hotkeys'"
assert_not_contains "already switched: nothing written" "$CALLS" "gsettings set"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_retarget "'my-own-script'"
assert_not_contains "slot 4 given another job by the user: left as it is" "$CALLS" "gsettings set"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_retarget "'/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://ohmydebn.org/hotkeys/'" ""
assert_not_contains "no custom-list from gsettings (no session): nothing written, so the next update tries again" "$CALLS" "gsettings set"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- Stock keybindings added since the marker (Console, custom-48, in
# 4.15.0): installs from before get just that slot, appended to
# custom-list, once - its own marker then keeps a user's removal from being
# undone by the next update. Nothing at all when it's already listed (only
# the marker), or when gsettings prints no list (not even the marker).
CONSOLE_SLOT="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-48/"
CONSOLE_MARKER="keybinding-add-48"
# run_marked <custom-list> [yes: the Console marker is already there]
run_marked() {
  mock_init
  setup_mocks
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER"
  [[ "${2:-}" == yes ]] && touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$CONSOLE_MARKER"
  MOCK_CUSTOM_LIST="$1" MOCK_CINNAMON_RUNNING=true run_script
  CALLS=$(cat "$MOCK_CALLS")
  LIST_SETS=$(grep 'gsettings set org.cinnamon.desktop.keybindings custom-list' "$MOCK_CALLS")
}
console_marked() {
  [ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/$CONSOLE_MARKER" ] && echo yes || echo no
}

run_marked "['custom-0', 'custom-47', 'custom5', 'custom-1000']"
assert_contains "Console missing: slot named Console" "$CALLS" "gsettings set $CONSOLE_SLOT name Console"
assert_contains "Console missing: runs ohmydebn-console" "$CALLS" "gsettings set $CONSOLE_SLOT command /usr/share/ohmydebn/bin/ohmydebn-console"
assert_contains "Console missing: bound to Super + the key left of 1, on any layout" "$CALLS" "gsettings set $CONSOLE_SLOT binding ['<Super>Above_Tab']"
assert_eq "Console missing: custom-list written twice" "2" "$(echo "$LIST_SETS" | wc -l)"
assert_contains "Console missing: first list write carries __dummy__ so Cinnamon reloads" "$(echo "$LIST_SETS" | head -1)" "'custom-1000', 'custom-48', '__dummy__']"
assert_contains "Console missing: final list keeps everything and adds custom-48" "$(echo "$LIST_SETS" | tail -1)" "['custom-0', 'custom-47', 'custom5', 'custom-1000', 'custom-48']"
assert_eq "Console missing: no other stock slot rewritten" "3" "$(grep -c 'gsettings set .*custom-keybindings/custom-[0-9]*/' "$MOCK_CALLS")"
assert_eq "Console missing: marked as added" "yes" "$(console_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Added once: a user who removed it in Cinnamon's settings keeps it removed.
run_marked "['custom-0', 'custom-47', 'custom-1000']" yes
assert_not_contains "Console added before, since removed by the user: not added back" "$CALLS" "gsettings set"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_marked "@as []"
assert_contains "empty custom-list: becomes just custom-48" "$(echo "$LIST_SETS" | tail -1)" "custom-list ['custom-48']"
assert_eq "empty custom-list: marked as added" "yes" "$(console_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_marked "['custom-0', 'custom-48', 'custom-1000']"
assert_not_contains "Console already listed: nothing written" "$CALLS" "gsettings set"
assert_eq "Console already listed: marked, so a later removal sticks" "yes" "$(console_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_marked ""
assert_not_contains "no list from gsettings: nothing written" "$CALLS" "gsettings set"
assert_eq "no list from gsettings: not marked, so the next update tries again" "no" "$(console_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- Stock keybindings removed since the marker (Antigravity, custom-34,
# in 4.15.0): installs from before have it listed, running a launcher
# that's gone. Taken out of the list once, only while it still runs
# ohmydebn-antigravity; a slot the user gave another job is left alone.
# The Console step is marked done throughout, so it adds nothing here.
ANTIGRAVITY_SLOT="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-34/"
REMOVE_MARKER="keybinding-remove-34"
# run_removed <custom-list> <slot 34's command> [yes: already marked]
run_removed() {
  mock_init
  setup_mocks
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$KEYBINDING_MARKER"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$CONSOLE_MARKER"
  [[ "${3:-}" == yes ]] && touch "$SCRATCH_HOME/.local/state/ohmydebn-config/$REMOVE_MARKER"
  MOCK_CUSTOM_LIST="$1" MOCK_SLOT=34 MOCK_SLOT_NAME="Antigravity" MOCK_SLOT_COMMAND="$2" MOCK_CINNAMON_RUNNING=true run_script
  CALLS=$(cat "$MOCK_CALLS")
  LIST_SETS=$(grep 'gsettings set org.cinnamon.desktop.keybindings custom-list' "$MOCK_CALLS")
}
removal_marked() {
  [ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/$REMOVE_MARKER" ] && echo yes || echo no
}

run_removed "['custom-0', 'custom-33', 'custom-34', 'custom-35', 'custom-48', 'custom5', 'custom-1000']" "/usr/share/ohmydebn/bin/ohmydebn-antigravity"
assert_eq "Antigravity listed: custom-list written twice" "2" "$(echo "$LIST_SETS" | wc -l)"
assert_contains "Antigravity listed: first list write carries __dummy__ so Cinnamon reloads" "$(echo "$LIST_SETS" | head -1)" "'custom-1000', '__dummy__']"
assert_contains "Antigravity listed: final list keeps everything else, without custom-34" "$(echo "$LIST_SETS" | tail -1)" \
  "custom-list ['custom-0', 'custom-33', 'custom-35', 'custom-48', 'custom5', 'custom-1000']"
assert_contains "Antigravity listed: its slot's settings cleared" "$CALLS" "gsettings reset-recursively $ANTIGRAVITY_SLOT"
assert_eq "Antigravity listed: marked as removed" "yes" "$(removal_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_removed "['custom-34']" "/usr/share/ohmydebn/bin/ohmydebn-antigravity"
assert_contains "Antigravity alone in the list: the list ends up empty" "$(echo "$LIST_SETS" | tail -1)" "custom-list []"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_removed "['custom-0', 'custom-34', 'custom-48']" "/usr/bin/my-own-thing"
assert_not_contains "slot 34 given another job by the user: nothing written" "$CALLS" "gsettings set"
assert_not_contains "slot 34 given another job by the user: its settings kept" "$CALLS" "reset-recursively"
assert_eq "slot 34 given another job by the user: marked, so it's never touched" "yes" "$(removal_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_removed "['custom-0', 'custom-48']" "/usr/share/ohmydebn/bin/ohmydebn-antigravity"
assert_not_contains "Antigravity not listed: nothing written" "$CALLS" "gsettings set"
assert_eq "Antigravity not listed: marked" "yes" "$(removal_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_removed "['custom-0', 'custom-34', 'custom-48']" "/usr/share/ohmydebn/bin/ohmydebn-antigravity" yes
assert_not_contains "already marked: slot 34 left as it is" "$CALLS" "gsettings set"
rm -rf "$SCRATCH_HOME"
mock_cleanup

run_removed "" "/usr/share/ohmydebn/bin/ohmydebn-antigravity"
assert_eq "no list from gsettings: not marked, so the next update tries again" "no" "$(removal_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# A new install: the full pass lists every stock slot, Console included, so
# the step after it only marks it.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
MOCK_CINNAMON_RUNNING=true run_script
assert_eq "new install: custom-list written only by the full pass (twice)" "2" "$(grep -c 'gsettings set org.cinnamon.desktop.keybindings custom-list' "$MOCK_CALLS")"
assert_eq "new install: Console marked as added" "yes" "$(console_marked)"
assert_eq "new install: Antigravity's removal marked" "yes" "$(removal_marked)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
