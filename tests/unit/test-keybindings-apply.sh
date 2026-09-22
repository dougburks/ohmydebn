#!/bin/bash
#
# Unit tests for bin/ohmydebn-keybindings-apply - the user's own keybindings file
# (~/.config/ohmydebn/keybindings.txt) layered on top of the stock keybindings.
#
# gsettings is replaced by a STATEFUL fake (values stored as files under
# $GS_STORE, so `get` returns what `set` wrote, and reset/reset-recursively
# delete) - the script reads back the live custom-list and stock slot
# bindings, so a log-only stub wouldn't exercise the interesting paths
# (collision stripping, restore-on-removal, list preservation). A small
# fake stock keybinding-custom.txt stands in for the real one.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-keybindings-apply"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-keybindings-apply ==="

CUSTOM_SCHEMA=org.cinnamon.desktop.keybindings.custom-keybinding
CUSTOM_PATH=/org/cinnamon/desktop/keybindings/custom-keybindings

setup() {
  mock_init
  SCRATCH_HOME=$(mktemp -d)
  GS_STORE="$MOCK_DIR/gs-store"
  STOCK="$MOCK_DIR/keybinding"
  mkdir -p "$GS_STORE" "$STOCK" "$SCRATCH_HOME/.config/ohmydebn"
  export GS_STORE
  USER_FILE="$SCRATCH_HOME/.config/ohmydebn/keybindings.txt"
  STATE="$SCRATCH_HOME/.local/state/ohmydebn-config"

  cat >"$STOCK/keybinding-custom.txt" <<'EOF'
keybinding-custom 0 "Browser" "/usr/share/ohmydebn/bin/ohmydebn-browser-tiled" "['<Super>B']" "Press Super + B for browser"
keybinding-custom 1 "Neovim" "/usr/share/ohmydebn/bin/ohmydebn-neovim" "['<Super>N']" "Press Super + N to launch Neovim text editor"
keybinding-custom 2 "X" "/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://x.com" "['<Super>X']" "Press Super + X for X.com"
keybinding-custom 3 "App Launcher" "/usr/share/ohmydebn/bin/ohmydebn-app-launcher" "['<Super>R', '<Super><Alt>space']" "Press Super + R (or Super + Alt + Space) to run the application launcher"
EOF
  cat >"$STOCK/keybinding-cinnamon.txt" <<'EOF'
keybinding-cinnamon "wm" "close" "['<Alt>F4', '<Super>w']" "Press Super + W to close a window"
EOF

  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
echo "== $* =="
EOF
  # Stateful fake gsettings. Keys are files named "<schema[:path]>__<key>"
  # with / and : flattened, so reset-recursively is a prefix delete.
  mock_bin gsettings <<'EOF'
#!/bin/bash
fname() { echo "$1__$2" | tr '/:' '__'; }
default_for() { case "$1" in custom-list | binding) echo "@as []" ;; *) echo "''" ;; esac; }
case "$1" in
list-schemas) exit 0 ;;
get)
  f="$GS_STORE/$(fname "$2" "$3")"
  if [ -f "$f" ]; then cat "$f"; else default_for "$3"; fi
  ;;
set)
  mock_log "set $2 $3 $4"
  case "$4" in
  \[*) printf '%s\n' "$4" ;;
  *) printf "'%s'\n" "$4" ;;
  esac >"$GS_STORE/$(fname "$2" "$3")"
  ;;
reset)
  mock_log "reset $2 $3"
  rm -f "$GS_STORE/$(fname "$2" "$3")"
  ;;
reset-recursively)
  mock_log "reset-recursively $2"
  rm -f "$GS_STORE/$(fname "$2" "")"*
  ;;
esac
exit 0
EOF

  # Seed what the stock pass would have written, plus one shortcut the user
  # added in Cinnamon Settings (custom5, Cinnamon's own no-hyphen naming).
  seed_slot 0 "Browser" "/usr/share/ohmydebn/bin/ohmydebn-browser-tiled" "['<Super>B']"
  seed_slot 1 "Neovim" "/usr/share/ohmydebn/bin/ohmydebn-neovim" "['<Super>N']"
  seed_slot 2 "X" "/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://x.com" "['<Super>X']"
  seed_slot 3 "App Launcher" "/usr/share/ohmydebn/bin/ohmydebn-app-launcher" "['<Super>R', '<Super><Alt>space']"
  gs set org.cinnamon.desktop.keybindings custom-list "['custom-0', 'custom-1', 'custom-2', 'custom-3', 'custom5']"
  gs set org.cinnamon.desktop.keybindings.wm close "['<Alt>F4', '<Super>w']"
  : >"$MOCK_CALLS"

  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn/install/keybinding#$STOCK#g" "$SCRIPT" >"$MOCK_DIR/apply-patched.sh"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

gs() { PATH="$(mock_path)" gsettings "$@"; }
slot() { gs get "$CUSTOM_SCHEMA:$CUSTOM_PATH/custom-$1/" "$2"; }
seed_slot() {
  gs set "$CUSTOM_SCHEMA:$CUSTOM_PATH/custom-$1/" name "$2"
  gs set "$CUSTOM_SCHEMA:$CUSTOM_PATH/custom-$1/" command "$3"
  gs set "$CUSTOM_SCHEMA:$CUSTOM_PATH/custom-$1/" binding "$4"
}
custom_list() { gs get org.cinnamon.desktop.keybindings custom-list; }

# run_apply [script args...]; STOCK_APPLIED=1 in the environment models the
# stock pass having just run in the same install.
run_apply() {
  OUTPUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" OHMYDEBN_KEYBINDINGS_STOCK_APPLIED="${STOCK_APPLIED:-}" bash "$MOCK_DIR/apply-patched.sh" "$@" 2>&1)
  EXIT_CODE=$?
}

# --- new keybinding: user slot, list preserved, reload toggle, state written ---
setup
echo 'keybinding "Slack" "/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://slack.com" "['"'"'<Super>S'"'"']"' >"$USER_FILE"
run_apply
assert_eq "new keybinding: exits 0" "0" "$EXIT_CODE"
assert_eq "new keybinding: lands in custom-1000" "'Slack'" "$(slot 1000 name)"
assert_eq "new keybinding: command written" "'/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://slack.com'" "$(slot 1000 command)"
assert_eq "new keybinding: binding written" "['<Super>S']" "$(slot 1000 binding)"
assert_eq "new keybinding: custom-list keeps stock, GUI-added and user slots" \
  "['custom-0', 'custom-1', 'custom-2', 'custom-3', 'custom5', 'custom-1000']" "$(custom_list)"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "new keybinding: custom-list toggled through __dummy__ so Cinnamon reloads" "$CALLS" "'custom-1000', '__dummy__']"
assert_contains "new keybinding: headline shown" "$CALLS" "ohmydebn-headline Applying your custom keybindings"
assert_contains "new keybinding: reported" "$OUTPUT" "Super + S: Slack"
assert_eq "new keybinding: hash state written" "$(sha256sum <"$USER_FILE" | cut -d' ' -f1)" "$(cat "$STATE/keybindings-user-sha256")"
assert_contains "new keybinding: user slot recorded for the doctor" "$(cat "$STATE/keybindings-user-touched")" "user 1000"
assert_eq "new keybinding: stock slots untouched" "'/usr/share/ohmydebn/bin/ohmydebn-neovim'" "$(slot 1 command)"

# --- --from-install gating on top of that state ---
: >"$MOCK_CALLS"
run_apply --from-install
assert_eq "from-install, unchanged file, no stock pass: exits 0" "0" "$EXIT_CODE"
assert_eq "from-install, unchanged file, no stock pass: does nothing" "" "$(cat "$MOCK_CALLS")"
assert_eq "from-install, unchanged file, no stock pass: prints nothing" "" "$OUTPUT"
: >"$MOCK_CALLS"
STOCK_APPLIED=1 run_apply --from-install
assert_contains "from-install after the stock pass: re-applies" "$(cat "$MOCK_CALLS")" "ohmydebn-headline Applying your custom keybindings"
: >"$MOCK_CALLS"
echo '# edited' >>"$USER_FILE"
run_apply --from-install
assert_contains "from-install with an edited file: re-applies" "$(cat "$MOCK_CALLS")" "ohmydebn-headline Applying your custom keybindings"

# --- deleting the file removes the user slot and the state ---
rm "$USER_FILE"
run_apply
assert_eq "file deleted: exits 0" "0" "$EXIT_CODE"
assert_contains "file deleted: says so" "$OUTPUT" "stock keybindings restored"
assert_eq "file deleted: user slot reset" "''" "$(slot 1000 name)"
assert_eq "file deleted: user slot dropped from custom-list, others kept" \
  "['custom-0', 'custom-1', 'custom-2', 'custom-3', 'custom5']" "$(custom_list)"
assert_eq "file deleted: hash state removed" "no" "$([ -f "$STATE/keybindings-user-sha256" ] && echo yes || echo no)"
assert_eq "file deleted: touched state removed" "no" "$([ -f "$STATE/keybindings-user-touched" ] && echo yes || echo no)"
: >"$MOCK_CALLS"
run_apply
assert_eq "no file, no state: prints nothing" "" "$OUTPUT"
assert_eq "no file, no state: touches nothing" "" "$(cat "$MOCK_CALLS")"
teardown

# --- override a stock keybinding by name, then remove the line: restored ---
setup
echo 'keybinding "Neovim" "/usr/bin/foo" "['"'"'<Super>V'"'"']"' >"$USER_FILE"
run_apply
assert_eq "override: stock slot's command changed in place" "'/usr/bin/foo'" "$(slot 1 command)"
assert_eq "override: stock slot's binding changed in place" "['<Super>V']" "$(slot 1 binding)"
assert_eq "override: name kept" "'Neovim'" "$(slot 1 name)"
assert_eq "override: no user slot allocated" "''" "$(slot 1000 name)"
assert_contains "override: recorded as touched" "$(cat "$STATE/keybindings-user-touched")" "custom 1"
assert_contains "override: reported as a stock change" "$OUTPUT" "Super + V: Neovim (stock keybinding changed)"
: >"$USER_FILE"
run_apply
assert_eq "line removed: stock command restored" "'/usr/share/ohmydebn/bin/ohmydebn-neovim'" "$(slot 1 command)"
assert_eq "line removed: stock binding restored" "['<Super>N']" "$(slot 1 binding)"
assert_contains "line removed: empty file noted" "$OUTPUT" "No keybindings defined"
assert_eq "line removed: nothing left touched" "no" "$([ -f "$STATE/keybindings-user-touched" ] && echo yes || echo no)"
teardown

# --- unbind a stock keybinding; unknown names warn ---
setup
printf 'keybinding-unbind "X"\nkeybinding-unbind "Nope"\n' >"$USER_FILE"
run_apply
assert_eq "unbind: exits 0 despite the unknown name" "0" "$EXIT_CODE"
assert_eq "unbind: binding emptied" "[]" "$(slot 2 binding)"
assert_eq "unbind: command kept" "'/usr/share/ohmydebn/bin/ohmydebn-launch-webapp https://x.com'" "$(slot 2 command)"
assert_contains "unbind: reported with the old key" "$OUTPUT" "X: unbound (was Super + X)"
assert_contains "unbind: unknown name warned" "$OUTPUT" 'Warning: keybinding-unbind "Nope": no stock keybinding has that name'
teardown

# --- a claimed key is stripped from the stock keybinding that had it ---
setup
printf 'keybinding "Slack" "/usr/bin/slack" "['"'"'<super>x'"'"']"\nkeybinding "Runner" "/usr/bin/runner" "['"'"'<Super>R'"'"']"\n' >"$USER_FILE"
run_apply
assert_eq "collision: whole binding stripped (case-insensitive match)" "[]" "$(slot 2 binding)"
assert_contains "collision: X's key reported in the stock spelling" "$OUTPUT" 'Super + X: removed from stock "X" (now Slack)'
assert_eq "collision: only the claimed chord stripped from a multi-key binding" "['<Super><Alt>space']" "$(slot 3 binding)"
assert_contains "collision: App Launcher's key reported" "$OUTPUT" 'Super + R: removed from stock "App Launcher" (now Runner)'
assert_eq "collision: user slots allocated in file order" "'Runner'" "$(slot 1001 name)"
: >"$USER_FILE"
run_apply
assert_eq "collision undone: X restored" "['<Super>X']" "$(slot 2 binding)"
assert_eq "collision undone: App Launcher restored" "['<Super>R', '<Super><Alt>space']" "$(slot 3 binding)"
teardown

# --- Cinnamon built-ins: applied, restored from stock or reset ---
setup
printf 'keybinding-cinnamon "wm" "close" "['"'"'<Alt>F4'"'"']"\nkeybinding-cinnamon "wm" "minimize" "['"'"'<Super>m'"'"']"\n' >"$USER_FILE"
run_apply
assert_eq "cinnamon: stock key changed" "['<Alt>F4']" "$(gs get org.cinnamon.desktop.keybindings.wm close)"
assert_eq "cinnamon: other key set" "['<Super>m']" "$(gs get org.cinnamon.desktop.keybindings.wm minimize)"
assert_contains "cinnamon: reported" "$OUTPUT" "Alt + F4: Cinnamon wm close"
: >"$USER_FILE"
: >"$MOCK_CALLS"
run_apply
assert_eq "cinnamon undone: key in keybinding-cinnamon.txt restored from it" "['<Alt>F4', '<Super>w']" "$(gs get org.cinnamon.desktop.keybindings.wm close)"
assert_contains "cinnamon undone: key not in the stock file reset to Cinnamon's default" "$(cat "$MOCK_CALLS")" "reset org.cinnamon.desktop.keybindings.wm minimize"
teardown

# --- a line pasted from keybinding-custom.txt: number ignored, matched by name ---
setup
echo 'keybinding-custom 99 "Neovim" "/usr/bin/foo" "['"'"'<Super>V'"'"']" "Press Super + V"' >"$USER_FILE"
run_apply
assert_eq "pasted stock line: overrides by name, not slot 99" "'/usr/bin/foo'" "$(slot 1 command)"
assert_eq "pasted stock line: slot 99 untouched" "''" "$(slot 99 command)"
teardown

# --- syntax error: warn, change nothing, keep retrying on later installs ---
setup
echo 'keybinding "Broken' >"$USER_FILE"
run_apply
assert_eq "syntax error: exits 0" "0" "$EXIT_CODE"
assert_contains "syntax error: warned" "$OUTPUT" "has a syntax error - your custom keybindings were not applied"
assert_eq "syntax error: nothing written" "" "$(cat "$MOCK_CALLS")"
assert_eq "syntax error: hash not recorded, so the next install tries again" "no" "$([ -f "$STATE/keybindings-user-sha256" ] && echo yes || echo no)"
teardown

# --- a stale user slot from a file copied off another machine is cleaned up ---
setup
seed_slot 1007 "Old" "/usr/bin/old" "['<Super>O']"
gs set org.cinnamon.desktop.keybindings custom-list "['custom-0', 'custom-1', 'custom-2', 'custom-3', 'custom-1007', '__dummy__']"
echo 'keybinding "Slack" "/usr/bin/slack" "['"'"'<Super>S'"'"']"' >"$USER_FILE"
run_apply
assert_eq "stale user slot: reset" "''" "$(slot 1007 name)"
assert_eq "stale user slot: list rebuilt without it or __dummy__" "['custom-0', 'custom-1', 'custom-2', 'custom-3', 'custom-1000']" "$(custom_list)"
teardown

# --- usage ---
setup
run_apply --bogus
assert_eq "bad flag: exits 2" "2" "$EXIT_CODE"
teardown

test_summary
