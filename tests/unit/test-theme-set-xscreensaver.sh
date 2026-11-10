#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-xscreensaver, which colors
# XScreenSaver's unlock dialog with the current theme. PATH is only the
# mocks plus the few real tools the hook uses, so whether XScreenSaver is
# "installed" is up to each test, not the machine running it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-xscreensaver"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-xscreensaver ==="

setup() {
  mock_init
  H="$MOCK_DIR/home"
  mkdir -p "$H" "$MOCK_DIR/tools"
  for t in bash grep head sed mkdir mktemp cat chmod mv rm; do
    ln -s "$(command -v "$t")" "$MOCK_DIR/tools/$t"
  done
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/hook"
  printf 'background = "#101010"\nforeground = "#eeeeee"\naccent = "#33cc99"\ncolor1 = "#cc3333"\ncolor4 = "#3366cc"\n' >"$MOCK_DIR/colors.toml"
  mock_bin xrdb <<'EOF2'
#!/bin/bash
mock_log "xrdb $*"
EOF2
  mock_bin ohmydebn-lock-screen-set <<'EOF2'
#!/bin/bash
echo "${MOCK_LOCK_SCREEN:-cinnamon}"
EOF2
}

installed() {
  mock_bin xscreensaver <<'EOF2'
#!/bin/bash
exit 0
EOF2
}

run_hook() {
  # Not env -i: the mocks log through the exported MOCK_* and mock_log.
  # DISPLAY is cleared so only the tests that set it have one.
  OUTPUT=$(env -u DISPLAY HOME="$H" PATH="$MOCK_BIN:$MOCK_DIR/tools" "$@" bash "$MOCK_DIR/hook" "${HOOK_ARGS[@]}" </dev/null 2>&1)
  EXIT_CODE=$?
  RESOURCES="$H/.config/ohmydebn/current/xscreensaver.Xresources"
}

# --- XScreenSaver not installed: nothing written ---
setup
HOOK_ARGS=("$MOCK_DIR/colors.toml")
run_hook
assert_eq "not installed: exits 0" "0" "$EXIT_CODE"
assert_eq "not installed: no resources file" "no" "$([ -e "$RESOURCES" ] && echo yes || echo no)"
mock_cleanup

# --- installed: the dialog takes the theme's colors ---
setup
installed
HOOK_ARGS=("$MOCK_DIR/colors.toml")
run_hook
FILE=$(cat "$RESOURCES" 2>/dev/null)
assert_eq "installed: exits 0" "0" "$EXIT_CODE"
assert_eq "installed: prints nothing" "" "$OUTPUT"
assert_contains "colors: dialog theme picked" "$FILE" "XScreenSaver.dialogTheme: default"
assert_contains "colors: background" "$FILE" "XScreenSaver*default.Dialog.background: #101010"
assert_contains "colors: foreground" "$FILE" "XScreenSaver*default.Dialog.foreground: #eeeeee"
assert_contains "colors: accent on the border" "$FILE" "XScreenSaver*default.Dialog.borderColor: #33cc99"
assert_contains "colors: errors in the theme's red" "$FILE" "XScreenSaver*default.Dialog.error.foreground: #cc3333"
# 10% of the way from #101010 to #eeeeee: 0x10 + (0xee - 0x10) / 10 = 0x26.
assert_contains "flat: field a shade lighter than the dialog" "$FILE" "XScreenSaver*default.Dialog.text.background: #262626"
assert_contains "flat: buttons the same shade" "$FILE" "XScreenSaver*default.Dialog.button.background: #262626"
assert_contains "flat: no bevels" "$FILE" "XScreenSaver*default.Dialog.shadowWidth: 0"
assert_contains "flat: smaller logo" "$FILE" "XScreenSaver*default.Dialog.logo.width: 80"
assert_contains "flat: thinner countdown bar" "$FILE" "XScreenSaver*default.Dialog.thermometer.width: 4"
assert_contains "flat: more padding" "$FILE" "XScreenSaver*default.Dialog.internalPadding: 32"
assert_contains "no hostname line (passwd.uname)" "$FILE" "XScreenSaver*passwd.uname: False"
assert_contains "asterisks while typing" "$FILE" "XScreenSaver*passwd.asterisks: True"
assert_contains "fonts: OhMyDebn's, then XScreenSaver's own" "$FILE" "XScreenSaver*Dialog.headingFont: CaskaydiaMono Nerd Font Bold 16, sans-serif bold 16"
assert_contains "fonts: every part of the dialog" "$(grep -c "^XScreenSaver\*Dialog\.[a-z]*Font: CaskaydiaMono Nerd Font" "$RESOURCES")" "7"
assert_eq "colors: written with mode 644" "644" "$(stat -c %a "$RESOURCES")"
assert_eq "colors: no temporary file left" "1" "$(ls "$H/.config/ohmydebn/current" | wc -l)"
assert_eq "Cinnamon's lock screen in use: not merged" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- XScreenSaver lock screen in use, under a display: merged now ---
setup
installed
HOOK_ARGS=("$MOCK_DIR/colors.toml")
run_hook MOCK_LOCK_SCREEN=xscreensaver DISPLAY=:0
assert_contains "in use: merged into the resource database" "$(cat "$MOCK_CALLS")" "xrdb -merge $H/.config/ohmydebn/current/xscreensaver.Xresources"
run_hook MOCK_LOCK_SCREEN=xscreensaver
assert_eq "in use, no display: merged once, from the run above only" "1" "$(grep -c "xrdb -merge" "$MOCK_CALLS")"
mock_cleanup

# --- a light theme: the shade is darker than the dialog ---
setup
installed
printf 'background = "#FAFAFA"\nforeground = "#212121"\naccent = "#3264eb"\n' >"$MOCK_DIR/colors.toml"
HOOK_ARGS=("$MOCK_DIR/colors.toml")
run_hook
# 0xfa - (0xfa - 0x21) / 10, rounded down: 0xe4.
assert_contains "light theme: a darker shade" "$(cat "$RESOURCES" 2>/dev/null)" "XScreenSaver*default.Dialog.text.background: #e4e4e4"
mock_cleanup

# --- colors that aren't #rrggbb: the shade is the dialog's own color ---
setup
installed
printf 'background = "#123"\nforeground = "#eeeeee"\naccent = "#33cc99"\n' >"$MOCK_DIR/colors.toml"
HOOK_ARGS=("$MOCK_DIR/colors.toml")
run_hook
assert_eq "short colors: still exits 0" "0" "$EXIT_CODE"
assert_contains "short colors: no shade, the background" "$(cat "$RESOURCES" 2>/dev/null)" "XScreenSaver*default.Dialog.text.background: #123"
mock_cleanup

# --- a theme without an accent: blue stands in ---
setup
installed
printf 'background = "#101010"\nforeground = "#eeeeee"\ncolor4 = "#3366cc"\n' >"$MOCK_DIR/colors.toml"
HOOK_ARGS=("$MOCK_DIR/colors.toml")
run_hook
FILE=$(cat "$RESOURCES" 2>/dev/null)
assert_contains "no accent: color4 instead" "$FILE" "XScreenSaver*default.Dialog.borderColor: #3366cc"
assert_contains "no red: a default red" "$FILE" "XScreenSaver*default.Dialog.error.foreground: #FF5555"
mock_cleanup

# --- no colors source (from ohmydebn-lock-screen-set): the current
# theme's, and the temporary file is deleted afterwards ---
setup
installed
cp "$MOCK_DIR/colors.toml" "$MOCK_DIR/temp-colors.toml"
mock_bin ohmydebn-theme-set-colors <<'EOF2'
#!/bin/bash
mock_log "colors $*"
echo "$MOCK_DIR/temp-colors.toml"
EOF2
mock_bin ohmydebn-theme-set-colors-delete <<'EOF2'
#!/bin/bash
mock_log "colors-delete $*"
EOF2
HOOK_ARGS=()
run_hook
assert_contains "no source: reads the current theme" "$(cat "$MOCK_CALLS")" "colors $H/.config/ohmydebn/current/theme"
assert_contains "no source: deletes the temporary colors" "$(cat "$MOCK_CALLS")" "colors-delete $MOCK_DIR/temp-colors.toml"
assert_contains "no source: still writes the colors" "$(cat "$RESOURCES" 2>/dev/null)" "background: #101010"
mock_cleanup

test_summary
