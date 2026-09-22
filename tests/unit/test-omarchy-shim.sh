#!/bin/bash
#
# Unit tests for bin/omarchy - the Omarchy CLI surface Aether >= 4.29.9
# drives (it looks up a single `omarchy` executable and runs `version`,
# `theme set <name>` and `theme bg set <path>`; see the shim's own comment)
# - and bin/ohmydebn-theme-bg-set, the "make this exact image the current
# background" helper it and ohmydebn-theme-bg-next share. ohmydebn-theme-set
# and gsettings are mocked and HOME is a scratch dir, so nothing here
# changes the real desktop.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/omarchy / bin/ohmydebn-theme-bg-set ==="

setup() {
  mock_init
  mock_bin ohmydebn-theme-set <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-theme-set $* [skip=${OMARCHY_THEME_SKIP_BACKGROUND:-unset}]"
EOF2
  mock_bin ohmydebn-theme-list <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-theme-list"
echo "hackerman"
EOF2
  mock_bin ohmydebn-version <<'EOF2'
#!/bin/bash
echo "4.8.0"
EOF2
  mock_bin gsettings <<'EOF2'
#!/bin/bash
mock_log "gsettings $*"
EOF2
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current"
  # The real bg-set is used (patched only for the bin path); the shim is
  # patched so its $BIN points at the mocks plus that patched bg-set.
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-theme-bg-set" >"$MOCK_BIN/ohmydebn-theme-bg-set"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/omarchy" >"$MOCK_BIN/omarchy"
  chmod +x "$MOCK_BIN/ohmydebn-theme-bg-set" "$MOCK_BIN/omarchy"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# run_shim <args...>; sets OUT and EXIT_CODE
run_shim() {
  OUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/omarchy" "$@" 2>&1)
  EXIT_CODE=$?
}

# --- version ---
setup
run_shim version
assert_eq "version: exits 0" "0" "$EXIT_CODE"
assert_eq "version: reports OhMyDebn's version" "ohmydebn 4.8.0" "$OUT"
teardown

# --- theme set ---
setup
run_shim theme set hackerman
assert_eq "theme set: exits 0" "0" "$EXIT_CODE"
assert_eq "theme set: delegates to ohmydebn-theme-set with the name, no background flag" \
  "ohmydebn-theme-set hackerman [skip=unset]" "$(cat "$MOCK_CALLS")"
teardown

# --- theme set with OMARCHY_THEME_SKIP_BACKGROUND=1 (Aether's wallpaper sequence) ---
setup
OUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" OMARCHY_THEME_SKIP_BACKGROUND=1 bash "$MOCK_BIN/omarchy" theme set aether-sunset 2>&1); EXIT_CODE=$?
assert_eq "theme set (skip bg): exits 0" "0" "$EXIT_CODE"
assert_eq "theme set (skip bg): passes --keep-background so the wallpaper Aether just set survives" \
  "ohmydebn-theme-set --keep-background aether-sunset [skip=1]" "$(cat "$MOCK_CALLS")"
teardown

# --- theme bg set <path> ---
setup
IMG="$SCRATCH_HOME/.config/ohmydebn/themes/aether-sunset/backgrounds/sunset.jpg"
mkdir -p "$(dirname "$IMG")" && printf 'jpg' >"$IMG"
run_shim theme bg set "$IMG"
assert_eq "bg set: exits 0" "0" "$EXIT_CODE"
assert_eq "bg set: current/background symlink points at the image" "$IMG" \
  "$(readlink "$SCRATCH_HOME/.config/ohmydebn/current/background")"
assert_contains "bg set: Cinnamon picture-uri set to the resolved file" "$(cat "$MOCK_CALLS")" \
  "gsettings set org.cinnamon.desktop.background picture-uri file://$IMG"
assert_not_contains "bg set: does not touch the theme" "$(cat "$MOCK_CALLS")" "ohmydebn-theme-set"
teardown

# --- theme bg set with a missing file: refuse, change nothing ---
setup
ln -s /somewhere/old.jpg "$SCRATCH_HOME/.config/ohmydebn/current/background"
run_shim theme bg set "$SCRATCH_HOME/does-not-exist.png"
assert_eq "bg set (missing): non-zero exit" "1" "$EXIT_CODE"
assert_contains "bg set (missing): says what's wrong" "$OUT" "background image not found"
assert_eq "bg set (missing): existing symlink untouched" "/somewhere/old.jpg" \
  "$(readlink "$SCRATCH_HOME/.config/ohmydebn/current/background")"
assert_eq "bg set (missing): gsettings not called" "" "$(cat "$MOCK_CALLS")"
teardown

# --- theme current / list ---
setup
echo "hackerman" >"$SCRATCH_HOME/.config/ohmydebn/current/theme.name"
run_shim theme current
assert_eq "theme current: prints the active theme name" "hackerman" "$OUT"
run_shim theme list
assert_eq "theme list: delegates to ohmydebn-theme-list" "ohmydebn-theme-list" "$(cat "$MOCK_CALLS")"
teardown

# --- unknown / malformed invocations: usage, exit 1, nothing run ---
setup
for args in "" "frobnicate" "theme" "theme set" "theme set a b" "theme bg" "theme bg set" "theme bg unset x"; do
  # shellcheck disable=SC2086
  run_shim $args
  assert_eq "usage for '$args': exits 1" "1" "$EXIT_CODE"
  assert_contains "usage for '$args': prints usage" "$OUT" "Usage: omarchy"
done
assert_eq "malformed invocations: nothing was executed" "" "$(cat "$MOCK_CALLS")"
teardown

test_summary
