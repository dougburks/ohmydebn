#!/bin/bash
#
# Unit tests for install/packaging/theme-intros.sh, which installs the
# theme intros package once: on a new install or the update that first
# offers it, never on a Raspberry Pi (intros don't play there), and not
# again after someone removes it. A run where it couldn't be installed
# tries again next time.
#
# sudo is mocked to log and then run its command, the marker directory is
# patched to a scratch one, and dpkg answers from MOCK_INSTALLED.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/packaging/theme-intros.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/packaging/theme-intros.sh ==="

setup() {
  mock_init
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
exec "$@"
EOF2
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF2
  # Installs what it's given unless MOCK_UNAVAILABLE, recording it as
  # installed for the dpkg stand-in.
  mock_bin ohmydebn-pkg-install-optional <<'EOF2'
#!/bin/bash
mock_log "install $*"
[[ -n "${MOCK_UNAVAILABLE:-}" ]] && exit 0
echo "$*" >>"$MOCK_DIR/installed"
EOF2
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == -s ]] && grep -qx "$2" "$MOCK_DIR/installed" 2>/dev/null
EOF2
  STATE="$MOCK_DIR/state/theme-intros-offered"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#^THEME_INTROS_STATE_DIR=.*#THEME_INTROS_STATE_DIR=$MOCK_DIR/state#" \
    "$SCRIPT" >"$MOCK_DIR/patched.sh"
}
run_script() {
  PATH="$(mock_path)" OHMYDEBN_TEST_DEVICE_TREE_MODEL="${MOCK_MODEL:-$MOCK_DIR/no-model}" \
    bash -e "$MOCK_DIR/patched.sh" </dev/null >"$MOCK_DIR/output" 2>&1
  echo $?
}
marked() { [ -f "$STATE" ] && echo yes || echo no; }

# --- first run: installed, and marked ---
setup
assert_eq "first run: exits 0" "0" "$(run_script)"
assert_contains "first run: the package is installed" "$(cat "$MOCK_CALLS")" "install ohmydebn-themes-omarchy-intros"
assert_contains "first run: says so" "$(cat "$MOCK_CALLS")" "ohmydebn-headline Installing theme intros"
assert_eq "first run: marked" "yes" "$(marked)"
assert_not_contains "first run: no error about the missing device-tree model" "$(cat "$MOCK_DIR/output")" "No such file"

# --- later runs: nothing, even after it's been removed ---
: >"$MOCK_CALLS"
rm "$MOCK_DIR/installed"
assert_eq "removed later: exits 0" "0" "$(run_script)"
assert_eq "removed later: not installed again" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- not available yet: tried again next time ---
setup
export MOCK_UNAVAILABLE=1
assert_eq "unavailable: exits 0" "0" "$(run_script)"
assert_eq "unavailable: not marked" "no" "$(marked)"
unset MOCK_UNAVAILABLE
: >"$MOCK_CALLS"
run_script >/dev/null
assert_contains "unavailable, then available: installed" "$(cat "$MOCK_CALLS")" "install ohmydebn-themes-omarchy-intros"
assert_eq "unavailable, then available: marked" "yes" "$(marked)"
mock_cleanup

# --- a Raspberry Pi: never installed ---
setup
printf 'Raspberry Pi 5 Model B Rev 1.0\0' >"$MOCK_DIR/model"
MOCK_MODEL="$MOCK_DIR/model"
assert_eq "Raspberry Pi: exits 0" "0" "$(run_script)"
assert_not_contains "Raspberry Pi: not installed" "$(cat "$MOCK_CALLS")" "install "
assert_eq "Raspberry Pi: marked, so it isn't reconsidered" "yes" "$(marked)"
unset MOCK_MODEL
mock_cleanup

test_summary
