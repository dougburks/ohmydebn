#!/bin/bash
#
# Unit tests for install/config/btop.sh's theme link. btop's
# themes/current.theme links to the current OhMyDebn theme's btop.theme,
# so btop follows theme switches. The link used to be made whenever the
# path wasn't a link, so a current.theme the user put there themselves
# was replaced on every update; now it's made only where nothing is.
#
# dpkg reports btop installed, the headline is mocked, HOME is a scratch
# directory, and OhMyDebn's own btop config comes from this repo.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/btop.sh ==="

setup() {
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "btop" ]] && exit 0
exit 1
EOF2
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
mock_log "headline $*"
EOF2
  SCRATCH_HOME=$(mktemp -d)
  THEME="$SCRATCH_HOME/.config/btop/themes/current.theme"
  # An existing user's: btop.sh's first run (no marker) sets the whole
  # ~/.config/btop aside for OhMyDebn's, which isn't what's tested here.
  existing_user() {
    mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config" "$(dirname "$THEME")"
    touch "$SCRATCH_HOME/.local/state/ohmydebn-config/btop-config-20250916"
  }
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" \
    "$REPO_ROOT/install/config/btop.sh" >"$MOCK_DIR/btop-patched.sh"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# Sourced under set -e, as the install does.
run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash -c 'set -e; source "$1"; echo "run finished"' _ "$MOCK_DIR/btop-patched.sh" </dev/null >"$MOCK_DIR/out" 2>&1
  assert_contains "the install carries on past btop.sh" "$(cat "$MOCK_DIR/out")" "run finished"
}

setup
run
assert_eq "new user: current.theme links to the OhMyDebn theme's" "$SCRATCH_HOME/.config/ohmydebn/current/theme/btop.theme" \
  "$(readlink "$THEME")"
teardown

setup
existing_user
echo 'theme[main_bg]="#000000"' >"$THEME"
run
assert_eq "a current.theme of the user's own: kept" 'theme[main_bg]="#000000"' "$(cat "$THEME")"
assert_eq "a current.theme of the user's own: not made a link" "no" "$([[ -L "$THEME" ]] && echo yes || echo no)"
teardown

setup
existing_user
ln -s /somewhere/else.theme "$THEME"
run
assert_eq "a link of the user's own: kept" "/somewhere/else.theme" "$(readlink "$THEME")"
teardown

test_summary
