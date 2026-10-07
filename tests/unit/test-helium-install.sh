#!/bin/bash
#
# Unit tests for bin/ohmydebn-helium-bin-install's profile seeding. OhMyDebn
# seeds Helium's ~/.config/net.imput.helium with its defaults, but only into
# a profile that doesn't exist yet: a purge leaves ~/.config alone, so a
# reinstall used to overwrite the user's own Helium preferences.
#
# dpkg reports Helium not installed, sudo/curl are loggers, and the
# OhMyDebn config and bin directories are scratch ones, so nothing here
# touches the real system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-helium-bin-install: profile seeding ==="

setup() {
  mock_init
  for CMD in sudo curl; do
    mock_bin "$CMD" <<'STUB'
#!/bin/bash
cat >/dev/null 2>&1 &
exit 0
STUB
  done
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 1
STUB
  mock_bin ohmydebn-browser-set-default <<'STUB'
#!/bin/bash
exit 0
STUB
  mkdir -p "$MOCK_DIR/config/net.imput.helium/Default" "$MOCK_DIR/home/.config"
  echo seeded >"$MOCK_DIR/config/net.imput.helium/Default/Preferences"
  sed "s#/usr/share/ohmydebn/config#$MOCK_DIR/config#g; s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" \
    "$REPO_ROOT/bin/ohmydebn-helium-bin-install" >"$MOCK_DIR/install"
}

run() {
  HOME="$MOCK_DIR/home" PATH="$(mock_path)" bash "$MOCK_DIR/install" <<<"" >/dev/null 2>&1
}

setup
run
assert_eq "no Helium profile yet: OhMyDebn's defaults seeded" "seeded" \
  "$(cat "$MOCK_DIR/home/.config/net.imput.helium/Default/Preferences" 2>/dev/null)"
mock_cleanup

setup
mkdir -p "$MOCK_DIR/home/.config/net.imput.helium/Default"
echo mine >"$MOCK_DIR/home/.config/net.imput.helium/Default/Preferences"
run
assert_eq "existing Helium profile (a reinstall): user's preferences kept" "mine" \
  "$(cat "$MOCK_DIR/home/.config/net.imput.helium/Default/Preferences")"
mock_cleanup

test_summary
