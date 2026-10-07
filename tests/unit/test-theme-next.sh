#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-next: it cycles to the theme after the
# current one, by name. The current theme comes from current/theme.name,
# which ohmydebn-theme-set writes - current/theme is a real directory now,
# not a symlink, and judging by that symlink made every run apply the
# second theme instead of cycling. ohmydebn-theme-set and notify-send are
# mocked, and the theme directories are scratch ones.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-next ==="

# setup <current theme name, or "" for none> <system themes...> -- <user themes...>
setup() {
  mock_init
  SCRATCH_HOME="$MOCK_DIR/home"
  SYSTEM_THEMES="$MOCK_DIR/system-themes"
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/themes" "$SCRATCH_HOME/.config/ohmydebn/current/theme" "$SYSTEM_THEMES"
  [[ -n "$1" ]] && echo "$1" >"$SCRATCH_HOME/.config/ohmydebn/current/theme.name"
  shift
  local dest="$SYSTEM_THEMES"
  for name in "$@"; do
    if [[ "$name" == "--" ]]; then
      dest="$SCRATCH_HOME/.config/ohmydebn/themes"
      continue
    fi
    mkdir -p "$dest/$name"
  done
  mock_bin ohmydebn-theme-set <<'STUB'
#!/bin/bash
mock_log "theme-set $*"
STUB
  mock_bin notify-send <<'STUB'
#!/bin/bash
exit 0
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn-themes/#$SYSTEM_THEMES/#g" \
    "$REPO_ROOT/bin/ohmydebn-theme-next" >"$MOCK_DIR/theme-next"
}

run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/theme-next" </dev/null >/dev/null 2>&1
}

setup "everforest" catppuccin everforest gruvbox
run
assert_eq "cycles to the theme after the current one" "theme-set gruvbox" "$(cat "$MOCK_CALLS")"
mock_cleanup

setup "gruvbox" catppuccin everforest gruvbox
run
assert_eq "wraps around after the last theme" "theme-set catppuccin" "$(cat "$MOCK_CALLS")"
mock_cleanup

# A user theme sharing a shipped theme's name is one theme, not two.
setup "everforest" catppuccin everforest gruvbox -- everforest mytheme
run
assert_eq "user and shipped themes with one name count once" "theme-set gruvbox" "$(cat "$MOCK_CALLS")"
mock_cleanup

setup "" catppuccin everforest gruvbox
run
assert_eq "no current theme recorded: starts at the first" "theme-set catppuccin" "$(cat "$MOCK_CALLS")"
mock_cleanup

test_summary
