#!/bin/bash
#
# Unit tests for bin/ohmydebn-power-user-install, which applies the
# power-user profile to an existing install. It used to say it removes
# "Firefox, LibreOffice, etc." and then also purge every AI tool, VPN and
# browser installed from the OhMyDebn menu. Now it lists exactly what it
# will remove (the distro's apps only), says menu apps are kept, and does
# nothing unless the answer is yes. The removal helper and the profile
# itself are mocked.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-power-user-install ==="

# setup <what --list prints>
setup() {
  mock_init
  printf '%s' "$1" >"$MOCK_DIR/list"
  mock_bin ohmydebn-pkg-remove-all-optional <<'STUB'
#!/bin/bash
mock_log "remove-all-optional $*"
cat "$MOCK_DIR/list"
STUB
  mkdir -p "$MOCK_DIR/root/install/packaging"
  printf '#!/bin/bash\nmock_log "power-user.sh POWER_USER=$POWER_USER DISTRO_APPS_ONLY=${POWER_USER_DISTRO_APPS_ONLY:-}"\n' >"$MOCK_DIR/root/install/packaging/power-user.sh"
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/share/ohmydebn/install#$MOCK_DIR/root/install#g" \
    "$REPO_ROOT/bin/ohmydebn-power-user-install" >"$MOCK_DIR/install.sh"
}

run() {
  OUTPUT=$(PATH="$(mock_path)" bash "$MOCK_DIR/install.sh" <<<"$1" 2>&1)
  STATUS=$?
}

setup "libreoffice
thunderbird"
run ""
assert_contains "lists exactly what will be removed" "$OUTPUT" "These apps will be removed:
  libreoffice
  thunderbird"
assert_contains "says which apps are kept" "$OUTPUT" "Apps that only come from the OhMyDebn menu"
assert_contains "and that listed apps go even if installed from the menu" "$OUTPUT" "removed even if you"
assert_contains "asks first, defaulting to no" "$OUTPUT" "Continue? [y/N]"
assert_contains "the list is the distro's apps only, and changes nothing" "$(cat "$MOCK_CALLS")" "remove-all-optional --distro-apps-only --list"
assert_not_contains "Enter alone: nothing is applied" "$(cat "$MOCK_CALLS")" "power-user.sh"
assert_eq "Enter alone: exits cleanly" "0" "$STATUS"
mock_cleanup

setup "libreoffice"
run "n"
assert_not_contains "'n': nothing is applied" "$(cat "$MOCK_CALLS")" "power-user.sh"
mock_cleanup

setup "libreoffice"
run "y"
assert_contains "'y': the profile is applied, removing only the listed apps" "$(cat "$MOCK_CALLS")" "power-user.sh POWER_USER=true DISTRO_APPS_ONLY=1"
mock_cleanup

# EOF at the prompt (Ctrl-C, or closed input): `read` fails and set -e
# stops the script before the profile is ever applied.
setup "libreoffice"
OUTPUT=$(PATH="$(mock_path)" bash "$MOCK_DIR/install.sh" </dev/null 2>&1)
STATUS=$?
assert_eq "cancelled (EOF): exits non-zero" "1" "$STATUS"
assert_not_contains "cancelled (EOF): the profile never runs" "$(cat "$MOCK_CALLS")" "power-user.sh"
mock_cleanup

setup ""
run "y"
assert_contains "nothing of the distro's installed: says so" "$OUTPUT" "nothing will be removed"
assert_contains "nothing of the distro's installed: the extras are still applied on 'y'" "$(cat "$MOCK_CALLS")" "power-user.sh"
mock_cleanup

test_summary
