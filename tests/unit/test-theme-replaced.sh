#!/bin/bash
#
# Unit tests for install/config/theme-replaced.sh: a user whose theme was
# Osaka Jade, which Omarchy 4.5 replaced with Jade Horse, is moved to Jade
# Horse once on update with a note, without an intro covering the update's
# terminal. Anyone else, an Osaka Jade of the user's own, or an update
# that hasn't yet installed the themes with Jade Horse is left alone.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STEP="$REPO_ROOT/install/config/theme-replaced.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/theme-replaced.sh ==="

# run_step <current theme name, or "" for none> <space-separated shipped themes>
run_step() {
  mock_init
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "headline $*"
EOF
  mock_bin ohmydebn-theme-set <<'EOF'
#!/bin/bash
mock_log "theme-set $*"
[[ -n "${MOCK_THEME_SET_FAILS:-}" ]] && exit 1
echo "${@: -1}" >"$HOME/.config/ohmydebn/current/theme.name"
EOF
  STOCK="$MOCK_DIR/stock"
  local theme
  for theme in $2; do mkdir -p "$STOCK/$theme"; done
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/share/ohmydebn-themes#$STOCK#g" "$STEP" >"$MOCK_DIR/step.sh"
  H="$MOCK_DIR/home"
  mkdir -p "$H/.config/ohmydebn/current" "$H/.config/ohmydebn/themes"
  [[ -n "${OWN_THEME:-}" ]] && mkdir -p "$H/.config/ohmydebn/themes/$OWN_THEME"
  NAME_FILE="$H/.config/ohmydebn/current/theme.name"
  [[ -n "$1" ]] && echo "$1" >"$NAME_FILE"
  OUTPUT=$(HOME="$H" PATH="$(mock_path)" bash -e "$MOCK_DIR/step.sh" </dev/null 2>&1)
  STATUS=$?
}

NEW_THEMES="jade-horse nord tokyo-night"

run_step osaka-jade "$NEW_THEMES"
CALLS=$(cat "$MOCK_CALLS")
assert_eq "osaka-jade: exits 0" "0" "$STATUS"
assert_contains "osaka-jade: says what's happening" "$CALLS" "headline Switching from Osaka Jade to Jade Horse"
assert_contains "osaka-jade: says why" "$OUTPUT" "Omarchy replaced its Osaka Jade theme with Jade Horse"
assert_contains "osaka-jade: says where to choose another" "$OUTPUT" "Appearance > Theme"
assert_contains "osaka-jade: switches to Jade Horse, without an intro" "$CALLS" "theme-set --no-intro jade-horse"
assert_eq "osaka-jade: the theme is now Jade Horse" "jade-horse" "$(cat "$NAME_FILE")"
mock_cleanup

# Run again after the switch: nothing more happens.
run_step jade-horse "$NEW_THEMES"
assert_eq "second run: nothing said" "" "$OUTPUT"
assert_not_contains "second run: no theme switch" "$(cat "$MOCK_CALLS")" "theme-set"
mock_cleanup

run_step nord "$NEW_THEMES"
assert_eq "another theme: nothing said" "" "$OUTPUT"
assert_not_contains "another theme: no theme switch" "$(cat "$MOCK_CALLS")" "theme-set"
mock_cleanup

run_step "" "$NEW_THEMES"
assert_eq "no theme set: exits 0" "0" "$STATUS"
assert_not_contains "no theme set: no theme switch" "$(cat "$MOCK_CALLS")" "theme-set"
mock_cleanup

# The old themes package (Osaka Jade, no Jade Horse) still installed: wait
# for the one that ships Jade Horse rather than switch to nothing.
run_step osaka-jade "osaka-jade nord"
assert_not_contains "old themes package: no theme switch" "$(cat "$MOCK_CALLS")" "theme-set"
assert_eq "old themes package: still Osaka Jade" "osaka-jade" "$(cat "$NAME_FILE")"
mock_cleanup

# An Osaka Jade of the user's own (one they installed or copied into their
# themes folder) is theirs to keep.
OWN_THEME=osaka-jade run_step osaka-jade "$NEW_THEMES"
assert_eq "user's own Osaka Jade: nothing said" "" "$OUTPUT"
assert_not_contains "user's own Osaka Jade: no theme switch" "$(cat "$MOCK_CALLS")" "theme-set"
mock_cleanup

# A failed switch doesn't stop the update, and says what to do instead.
MOCK_THEME_SET_FAILS=1 run_step osaka-jade "$NEW_THEMES"
assert_eq "switch fails: exits 0" "0" "$STATUS"
assert_contains "switch fails: says to choose a theme" "$OUTPUT" "Couldn't switch to Jade Horse"
mock_cleanup

test_summary
