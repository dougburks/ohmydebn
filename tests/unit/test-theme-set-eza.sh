#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-eza. ~/.config/eza/theme.yml is
# OhMyDebn's link to the current theme's eza.yml, removed when a theme has
# none. A theme.yml of the user's own, or their own link to one, is left
# alone: switching to a theme without an eza.yml used to delete it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-eza ==="

# setup <theme has eza.yml: yes|no> <what's at theme.yml: none|ours|file|own-link>
setup() {
  SCRATCH_HOME=$(mktemp -d)
  THEME_YML="$SCRATCH_HOME/.config/eza/theme.yml"
  EZA_YML="$SCRATCH_HOME/.config/ohmydebn/current/theme/eza.yml"
  mkdir -p "$(dirname "$THEME_YML")" "$(dirname "$EZA_YML")"
  [[ $1 == yes ]] && echo "colours: theme" >"$EZA_YML"
  case "$2" in
  ours) ln -s "$EZA_YML" "$THEME_YML" ;;
  file) echo "colours: mine" >"$THEME_YML" ;;
  own-link) echo "colours: mine" >"$SCRATCH_HOME/dotfiles.yml" && ln -s "$SCRATCH_HOME/dotfiles.yml" "$THEME_YML" ;;
  esac
}

run() {
  HOME="$SCRATCH_HOME" bash "$REPO_ROOT/bin/ohmydebn-theme-set-eza" </dev/null >/dev/null 2>&1
  STATUS=$?
}

setup yes none
run
assert_eq "no theme.yml, theme has eza.yml: linked" "$EZA_YML" "$(readlink "$THEME_YML")"
rm -rf "$SCRATCH_HOME"

setup no ours
run
assert_eq "OhMyDebn's link, theme without eza.yml: removed" "no" \
  "$([ -e "$THEME_YML" ] || [ -L "$THEME_YML" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"

for has in yes no; do
  setup "$has" file
  run
  assert_eq "user's own theme.yml (theme eza.yml: $has): exits 0" "0" "$STATUS"
  assert_eq "user's own theme.yml (theme eza.yml: $has): kept" "colours: mine" "$(cat "$THEME_YML")"
  assert_eq "user's own theme.yml (theme eza.yml: $has): not made a link" "no" "$([ -L "$THEME_YML" ] && echo yes || echo no)"
  rm -rf "$SCRATCH_HOME"

  setup "$has" own-link
  run
  assert_eq "user's own link (theme eza.yml: $has): kept" "$SCRATCH_HOME/dotfiles.yml" "$(readlink "$THEME_YML")"
  rm -rf "$SCRATCH_HOME"
done

test_summary
