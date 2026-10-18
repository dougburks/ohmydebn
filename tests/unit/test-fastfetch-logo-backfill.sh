#!/bin/bash
#
# Unit tests for the fastfetch logo backfill in install/config/theme.sh.
# An upgrader's active theme has a config.jsonc templated before the
# template had a "logo" block, and templates never overwrite, so fastfetch
# would keep showing the distro logo until the next theme change. The
# backfill regenerates that config once, only when it's OhMyDebn's own
# (it has the OhMyDebn Website line) and has no logo yet. The colored logo
# itself (ohmydebn-theme-set-fastfetch) is refreshed on every run.
#
# The other once-only blocks in theme.sh are pre-marked done, as in
# test-picker-colors-backfill.sh.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/theme.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/theme.sh: fastfetch logo backfill ==="

MARKER=fastfetch-logo-backfill-20261015

setup() {
  mock_init
  # Stands in for the real templating: writes a config with a logo, as
  # the current template does, but only when none exists.
  mock_bin ohmydebn-theme-set-templates <<'MOCK'
#!/bin/bash
mock_log "theme-set-templates $*"
[ -f "$1/config.jsonc" ] || echo '{ "logo": {}, "key": "OhMyDebn Website" }' >"$1/config.jsonc"
MOCK
  mock_bin ohmydebn-theme-set-fastfetch <<'MOCK'
#!/bin/bash
mock_log "theme-set-fastfetch"
MOCK
  for stub in ohmydebn-theme-set-colors ohmydebn-theme-set-picker ohmydebn-theme-set-colors-delete ohmydebn-theme-set-neovim ohmydebn-theme-set-starship; do
    printf '#!/bin/bash\n' | mock_bin "$stub"
  done
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/theme-patched.sh"
  SCRATCH_HOME=$(mktemp -d)
  STATE="$SCRATCH_HOME/.local/state/ohmydebn-config"
  THEME="$SCRATCH_HOME/.config/ohmydebn/current/theme"
  mkdir -p "$STATE" "$THEME"
  touch "$SCRATCH_HOME/.local/state/ohmydebn"
  for m in omarchy-theme-symlink-20260325 omarchy-theme-url-handler-20260814 \
    fastfetch-config-backfill-20260817 nvim-theme-backfill-20260926 picker-colors-backfill-20260825; do
    touch "$STATE/$m"
  done
}

run_theme() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/theme-patched.sh" </dev/null >"$MOCK_DIR/out" 2>&1
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# Scenario 1: an upgrader's templated config with no logo - regenerated.
setup
printf '{\n  "display": {},\n  "key": "OhMyDebn Website"\n}\n' >"$THEME/config.jsonc"
run_theme
assert_contains "old config: templates rerun on the active theme" "$(cat "$MOCK_CALLS")" \
  "theme-set-templates $THEME"
assert_contains "old config: regenerated with the logo" "$(cat "$THEME/config.jsonc")" '"logo"'
assert_contains "old config: colored logo written" "$(cat "$MOCK_CALLS")" "theme-set-fastfetch"
assert_eq "old config: marker written" "yes" "$([ -f "$STATE/$MARKER" ] && echo yes || echo no)"
teardown

# Scenario 2: a config a theme ships itself (not ours) is left alone.
setup
echo '{ "modules": ["os"] }' >"$THEME/config.jsonc"
run_theme
assert_eq "theme's own config: untouched" '{ "modules": ["os"] }' "$(cat "$THEME/config.jsonc")"
assert_not_contains "theme's own config: no templating" "$(cat "$MOCK_CALLS")" "theme-set-templates"
teardown

# Scenario 3: already has a logo - left alone.
setup
echo '{ "logo": { "type": "builtin" }, "key": "OhMyDebn Website" }' >"$THEME/config.jsonc"
run_theme
assert_eq "config with a logo: untouched" '{ "logo": { "type": "builtin" }, "key": "OhMyDebn Website" }' \
  "$(cat "$THEME/config.jsonc")"
teardown

# Scenario 4: marker already there - the config isn't touched again, but
# the colored logo is still refreshed.
setup
touch "$STATE/$MARKER"
printf '{ "key": "OhMyDebn Website" }\n' >"$THEME/config.jsonc"
run_theme
assert_eq "marker present: config untouched" '{ "key": "OhMyDebn Website" }' "$(cat "$THEME/config.jsonc")"
assert_eq "marker present: colored logo still refreshed" "theme-set-fastfetch" "$(cat "$MOCK_CALLS")"
teardown

# Scenario 5: no active theme - nothing to regenerate, marker still written.
setup
rm -rf "$THEME"
run_theme
assert_not_contains "no theme: no templating" "$(cat "$MOCK_CALLS")" "theme-set-templates"
assert_eq "no theme: marker written" "yes" "$([ -f "$STATE/$MARKER" ] && echo yes || echo no)"
teardown

test_summary
