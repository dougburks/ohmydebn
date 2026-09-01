#!/bin/bash
#
# Unit tests for bin/ohmydebn-webapp-remove's handling of legacy nested
# launchers. ohmydebn-webapp-install didn't always guard against '/' in the
# app name, so some real installs may have a launcher like
# ~/.local/share/applications/foo/bar.desktop from before that guard
# existed. The interactive scan used to reduce a discovered launcher's path
# down to basename() before offering it for removal, which meant selecting
# "bar" tried to delete a top-level $DESKTOP_DIR/bar.desktop that never
# existed - the real nested file was untouched and unremovable. gum is
# stubbed out so the interactive picker path is exercised without a
# terminal.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-webapp-remove"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-webapp-remove ==="

fresh_scratch_home() {
  [[ -n "${SCRATCH_HOME:-}" ]] && rm -rf "$SCRATCH_HOME"
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/share/applications/icons"
}

make_launcher() {
  local rel="$1"
  mkdir -p "$SCRATCH_HOME/.local/share/applications/$(dirname "$rel")"
  cat >"$SCRATCH_HOME/.local/share/applications/$rel.desktop" <<EOF
[Desktop Entry]
Exec=ohmydebn-launch-webapp https://example.com
EOF
  mkdir -p "$SCRATCH_HOME/.local/share/applications/icons/$(dirname "$rel")"
  touch "$SCRATCH_HOME/.local/share/applications/icons/$rel.png"
}

# gum choose picks whatever $MOCK_GUM_CHOICE names, ignoring the offered
# option list - good enough to drive the picker deterministically. Bash
# can't export an array, so this is a single newline-free choice per run.
mock_gum_choosing() {
  mock_bin gum <<'EOF'
#!/bin/bash
if [[ "$1" == "choose" ]]; then
  echo "$MOCK_GUM_CHOICE"
fi
EOF
}

run_remove_interactive() {
  export MOCK_GUM_CHOICE
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$SCRIPT" >/dev/null 2>&1
}

run_remove_args() {
  HOME="$SCRATCH_HOME" bash "$SCRIPT" "$@" >/dev/null 2>&1
}

mock_init
mock_gum_choosing

# --- A legacy nested launcher is offered and removed by its real path ---
fresh_scratch_home
make_launcher "foo/bar"
MOCK_GUM_CHOICE="foo/bar"
run_remove_interactive
assert_eq "removes the nested desktop file" "" "$(find "$SCRATCH_HOME/.local/share/applications" -name '*.desktop')"
assert_eq "removes the nested icon" "" "$(find "$SCRATCH_HOME/.local/share/applications/icons" -name '*.png')"

# --- An ordinary (non-nested) launcher still works via the picker ---
fresh_scratch_home
make_launcher "Good App"
MOCK_GUM_CHOICE="Good App"
run_remove_interactive
assert_eq "removes an ordinary desktop file" "" "$(find "$SCRATCH_HOME/.local/share/applications" -name '*.desktop')"

# --- Command-line args still refuse a '/' in the name (untrusted input) ---
fresh_scratch_home
make_launcher "foo/bar"
OUTPUT=$(run_remove_args "foo/bar"; find "$SCRATCH_HOME/.local/share/applications" -name '*.desktop')
assert_contains "CLI arg with '/' leaves the nested file in place" "$OUTPUT" "bar.desktop"

rm -rf "$SCRATCH_HOME"
mock_cleanup
test_summary
