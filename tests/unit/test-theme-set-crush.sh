#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-crush, which publishes the OhMyDebn
# theme as a Crush theme file (~/.config/crush/themes/ohmydebn.json) and,
# with --activate, selects it once in ~/.config/crush/crush.json; and for
# install/config/crush.sh, which runs that for installs that had Crush
# before the hook.
#
# Crush's color tokens come from the theme's colors; the shades between
# background and foreground are mixed from those two, so a black/white
# theme gives exact values to check. A theme picked in Crush itself is
# saved to a different file that Crush reads last, so the selection here
# never has to replace one; it only keeps an active_theme the user put in
# crush.json themselves.
#
# Crush itself is a mock binary; HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-crush, install/config/crush.sh ==="

setup() {
  mock_init
  SCRATCH_HOME=$(mktemp -d)
  THEME="$SCRATCH_HOME/.config/crush/themes/ohmydebn.json"
  CONFIG="$SCRATCH_HOME/.config/crush/crush.json"
  MARKER="$SCRATCH_HOME/.local/state/ohmydebn-config/crush-theme-20261029"
  printf '#!/bin/bash\n' | mock_bin crush
  sed "s#/usr/bin/crush#$MOCK_BIN/crush#g" "$REPO_ROOT/bin/ohmydebn-theme-set-crush" >"$MOCK_BIN/ohmydebn-theme-set-crush"
  chmod +x "$MOCK_BIN/ohmydebn-theme-set-crush"
  # A dark theme in Omarchy 4's semantic format: black and white, so every
  # mixed shade is an exact gray.
  COLORS="$SCRATCH_HOME/colors.toml"
  cat >"$COLORS" <<'EOF2'
mode = "dark"
accent = "#0a0a0a"
muted = "#808080"
background = "#000000"
foreground = "#ffffff"
bright_foreground = "#fefefe"
red = "#110000"
green = "#001100"
yellow = "#111100"
blue = "#0000ff"
magenta = "#110011"
cyan = "#001111"
orange = "#ff8000"
bright_red = "#220000"
bright_green = "#002200"
bright_yellow = "#222200"
bright_blue = "#000022"
bright_magenta = "#220022"
bright_cyan = "#002222"
EOF2
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# run [args...]
run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-theme-set-crush" "$@" </dev/null >"$MOCK_DIR/out" 2>&1
  STATUS=$?
}

token() {
  jq -r --arg k "$1" '.[$k]' "$THEME"
}

# --- Crush not installed: nothing written ---
setup
rm "$MOCK_BIN/crush"
run --activate "$COLORS" false
assert_eq "no Crush: exits 0" "0" "$STATUS"
assert_eq "no Crush: no ~/.config/crush" "no" "$([ -e "$SCRATCH_HOME/.config/crush" ] && echo yes || echo no)"
assert_eq "no Crush: no marker" "no" "$([ -e "$MARKER" ] && echo yes || echo no)"
teardown

# --- the mapping ---
setup
run "$COLORS" false
assert_eq "theme: exits 0" "0" "$STATUS"
for pair in primary=#0a0a0a secondary=#110011 accent=#001100 keyword=#ff8000 \
  fg_base=#ffffff fg_subtle=#cccccc fg_more_subtle=#a8a8a8 fg_most_subtle=#7a7a7a \
  bg_base=#000000 bg_least_visible=#0f0f0f bg_less_visible=#1a1a1a bg_most_visible=#333333 \
  on_primary=#000000 separator=#333333 destructive=#220000 error=#110000 \
  warning=#111100 warning_subtle=#222200 attention=#ff8000 busy=#222200 \
  info=#0000ff info_more_subtle=#000022 info_most_subtle=#000099 \
  success=#001100 success_more_subtle=#002200 success_most_subtle=#001111 \
  diff_insert_fg=#001100 diff_delete_fg=#110000 yolo=#111100 plan=#110011 plan_more_subtle=#333333 \
  button=#0a0a0a button_subtle=#1a1a1a button_inactive=#333333 button_hovered=#808080; do
  assert_eq "theme: ${pair%%=*}" "${pair#*=}" "$(token "${pair%%=*}")"
done
# Without color0-15, the ANSI tokens are what the terminal gets from the
# same keys (see ohmydebn-theme-set-colors).
for pair in ansi_black=#000000 ansi_red=#110000 ansi_green=#001100 ansi_yellow=#111100 \
  ansi_blue=#0000ff ansi_magenta=#110011 ansi_cyan=#001111 ansi_white=#ffffff \
  ansi_bright_black=#808080 ansi_bright_red=#220000 ansi_bright_green=#002200 \
  ansi_bright_yellow=#222200 ansi_bright_blue=#000022 ansi_bright_magenta=#220022 \
  ansi_bright_cyan=#002222 ansi_bright_white=#fefefe; do
  assert_eq "theme: ${pair%%=*}" "${pair#*=}" "$(token "${pair%%=*}")"
done
assert_eq "theme: every token above, and nothing else (Crush derives the diff backgrounds)" "51" "$(jq 'length' "$THEME")"
assert_eq "theme: every value a #rrggbb color" "true" \
  "$(jq '[.[] | test("^#[0-9a-f]{6}$")] | all' "$THEME")"
assert_eq "theme: no temporary file left" "" "$(find "$(dirname "$THEME")" -name 'ohmydebn.json.*')"
assert_eq "theme without --activate: crush.json not written" "no" "$([ -e "$CONFIG" ] && echo yes || echo no)"
teardown

# --- a light theme: the mixed shades move toward the dark foreground ---
setup
sed -i 's/^background = .*/background = "#ffffff"/; s/^foreground = .*/foreground = "#000000"/' "$COLORS"
run "$COLORS" true
assert_eq "light: dimmer text is lighter" "#333333" "$(token fg_subtle)"
assert_eq "light: panels are darker than the background" "#f0f0f0" "$(token bg_least_visible)"
teardown

# --- a normalized colors.toml: ANSI tokens are its color0-15 exactly ---
setup
for n in $(seq 0 15); do printf 'color%d = "#0000%02x"\n' "$n" "$n"; done >>"$COLORS"
run "$COLORS" false
assert_eq "normalized: ansi_black is color0" "#000000" "$(token ansi_black)"
assert_eq "normalized: ansi_white is color7" "#000007" "$(token ansi_white)"
assert_eq "normalized: ansi_bright_white is color15" "#00000f" "$(token ansi_bright_white)"
assert_eq "normalized: semantic tokens still use the semantic keys" "#110000" "$(token error)"
teardown

# --- fallbacks ---
setup
sed -i '/^orange = /d' "$COLORS"
run "$COLORS" false
assert_eq "no orange: keyword is yellow" "#111100" "$(token keyword)"
assert_eq "no orange: attention is yellow" "#111100" "$(token attention)"
teardown

setup
sed -i 's/^accent = .*/accent = "blue"/' "$COLORS"
run "$COLORS" false
assert_eq "invalid accent and no color4: exits 0" "0" "$STATUS"
assert_contains "invalid accent: says why" "$(cat "$MOCK_DIR/out")" "missing background/foreground/accent"
assert_eq "invalid accent: no theme file" "no" "$([ -e "$THEME" ] && echo yes || echo no)"
teardown

setup
run "$SCRATCH_HOME/missing.toml" false
assert_eq "no colors file: exits 0" "0" "$STATUS"
assert_eq "no colors file: no theme file" "no" "$([ -e "$THEME" ] && echo yes || echo no)"
teardown

# --- a theme switch replaces the file ---
setup
run "$COLORS" false
sed -i 's/^accent = .*/accent = "#123456"/' "$COLORS"
run "$COLORS" false
assert_eq "rerun: new colors" "#123456" "$(token primary)"
teardown

# --- --activate: selects it once, keeping the user's settings ---
setup
run --activate "$COLORS" false
assert_eq "activate, no crush.json: created selecting ohmydebn" '{"options":{"tui":{"active_theme":"ohmydebn"}}}' \
  "$(jq -c . "$CONFIG")"
assert_eq "activate: marker set" "yes" "$([ -f "$MARKER" ] && echo yes || echo no)"
teardown

setup
mkdir -p "$(dirname "$CONFIG")"
echo '{"providers":{"openai":{"api_key":"$OPENAI_API_KEY"}},"options":{"tui":{"compact_mode":true}}}' >"$CONFIG"
run --activate "$COLORS" false
assert_eq "activate, existing crush.json: ohmydebn selected" "ohmydebn" "$(jq -r '.options.tui.active_theme' "$CONFIG")"
assert_eq "activate: providers kept" '$OPENAI_API_KEY' "$(jq -r '.providers.openai.api_key' "$CONFIG")"
assert_eq "activate: other TUI options kept" "true" "$(jq -r '.options.tui.compact_mode' "$CONFIG")"
assert_eq "activate: no temporary file left" "" "$(find "$(dirname "$CONFIG")" -maxdepth 1 -name 'crush.json.*')"
teardown

setup
mkdir -p "$(dirname "$CONFIG")"
echo '{"options":{"tui":{"active_theme":"keanu"}}}' >"$CONFIG"
run --activate "$COLORS" false
assert_eq "activate: a theme the user set in crush.json kept" '{"options":{"tui":{"active_theme":"keanu"}}}' "$(cat "$CONFIG")"
teardown

setup
mkdir -p "$(dirname "$CONFIG")"
printf '{\n  // mine\n  "options": {}\n}\n' >"$CONFIG"
BEFORE=$(cat "$CONFIG")
run --activate "$COLORS" false
assert_eq "activate: a crush.json jq can't read is left alone" "$BEFORE" "$(cat "$CONFIG")"
assert_eq "activate, unreadable crush.json: no temporary file left" "" \
  "$(find "$(dirname "$CONFIG")" -maxdepth 1 -name 'crush.json.*')"
teardown

setup
mkdir -p "$(dirname "$CONFIG")" "$(dirname "$MARKER")"
touch "$MARKER"
echo '{"options":{}}' >"$CONFIG"
run --activate "$COLORS" false
assert_eq "activate, marker set: crush.json not touched" '{"options":{}}' "$(cat "$CONFIG")"
assert_eq "activate, marker set: the theme file is still written" "#0a0a0a" "$(token primary)"
teardown

# --- install/config/crush.sh: selects it for existing installs, never stops the install ---
for hook_status in 0 1; do
  mock_init
  printf '#!/bin/bash\nmock_log "theme-set-crush $*"\nexit %s\n' "$hook_status" | mock_bin ohmydebn-theme-set-crush
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/install/config/crush.sh" >"$MOCK_DIR/crush-patched.sh"
  OUT=$(PATH="$(mock_path)" bash -c 'set -e; source "$1"; echo "run finished"' _ "$MOCK_DIR/crush-patched.sh" </dev/null 2>&1)
  assert_eq "crush.sh (hook exits $hook_status): runs the hook with --activate" "theme-set-crush --activate" "$(cat "$MOCK_CALLS")"
  assert_contains "crush.sh (hook exits $hook_status): the install carries on" "$OUT" "run finished"
  mock_cleanup
done

test_summary
