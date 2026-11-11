#!/bin/bash
#
# Unit tests for bin/ohmydebn-pkg-available and the installers that use it
# (Deskflow, AbiWord, rclone, Firefox). They installed from the distro's
# repositories without checking that it had the package, so where it
# didn't (no deskflow before Ubuntu 25.04, no abiword or rclone on Kali, no
# firefox-esr on Ubuntu, Mint or Pop!_OS) the menu item ended in apt's
# "Unable to locate package". apt-cache answers from MOCK_CANDIDATE (the
# packages with a candidate) and MOCK_NONE (known only as a name); sudo and
# the other OhMyDebn helpers only log.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-pkg-available, and installers of packages a distro may lack ==="

setup() {
  mock_init
  printf 'ID=ubuntu\nPRETTY_NAME="Ubuntu 24.04.3 LTS"\n' >"$MOCK_DIR/os-release"
  mock_bin apt-cache <<'STUB'
#!/bin/bash
[ "$1" = policy ] || exit 1
echo "$2:"
if [[ " ${MOCK_SNAP_STUB:-} " == *" $2 "* ]]; then
  echo "  Installed: (none)"
  echo "  Candidate: 1:1snap1-0ubuntu5"
elif [[ " ${MOCK_CANDIDATE:-} " == *" $2 "* ]]; then
  echo "  Installed: (none)"
  echo "  Candidate: 1.0-1"
elif [[ " ${MOCK_NONE:-} " == *" $2 "* ]]; then
  echo "  Installed: (none)"
  echo "  Candidate: (none)"
fi
STUB
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 1
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
STUB
  mock_bin snap <<'STUB'
#!/bin/bash
exit 1
STUB
  mock_bin ohmydebn-browser-set-default <<'STUB'
#!/bin/bash
mock_log "ohmydebn-browser-set-default $*"
STUB
  cp "$REPO_ROOT/bin/ohmydebn-pkg-available" "$MOCK_BIN/"
}
run() {
  OUT=$(OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" MOCK_CANDIDATE="${MOCK_CANDIDATE:-}" MOCK_NONE="${MOCK_NONE:-}" \
    MOCK_SNAP_STUB="${MOCK_SNAP_STUB:-}" \
    PATH="$(mock_path)" bash "$@" </dev/null 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

# --- the helper ---
setup
MOCK_CANDIDATE=deskflow run "$MOCK_BIN/ohmydebn-pkg-available" deskflow Deskflow
assert_eq "has a candidate: exits 0" "0" "$STATUS"
assert_eq "has a candidate: says nothing" "" "$OUT"
run "$MOCK_BIN/ohmydebn-pkg-available" deskflow Deskflow
assert_eq "unknown package: exits 1" "1" "$STATUS"
assert_contains "unknown package: says why, naming the distro" "$OUT" \
  "Deskflow can't be installed here: Ubuntu 24.04.3 LTS's repositories have no"
assert_contains "unknown package: names the package" "$OUT" "deskflow package."
MOCK_NONE=deskflow run "$MOCK_BIN/ohmydebn-pkg-available" deskflow Deskflow
assert_eq "only a name other packages mention (Candidate: (none)): exits 1" "1" "$STATUS"
run "$MOCK_BIN/ohmydebn-pkg-available" deskflow
assert_eq "no app name: exits 1" "1" "$STATUS"
assert_eq "no app name: says nothing" "" "$OUT"
mock_cleanup

# --- the installers ---
for spec in "deskflow deskflow Deskflow" "abiword abiword AbiWord" "rclone rclone rclone" "firefox-esr firefox-esr Firefox"; do
  read -r app pkg name <<<"$spec"
  for flags in "" --skip-prompt; do
    setup
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-$app-install" >"$MOCK_DIR/install"
    run "$MOCK_DIR/install" $flags
    assert_eq "$app $flags, distro lacks it: exits 1" "1" "$STATUS"
    assert_contains "$app $flags, distro lacks it: says why" "$OUT" "$name can't be installed here"
    assert_not_contains "$app $flags, distro lacks it: no Press Enter" "$OUT" "Press Enter"
    assert_not_contains "$app $flags, distro lacks it: nothing run as root" "$CALLS" "sudo"
    mock_cleanup
  done

  setup
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-$app-install" >"$MOCK_DIR/install"
  MOCK_CANDIDATE=$pkg run "$MOCK_DIR/install" --skip-prompt
  assert_eq "$app, distro has it: exits 0" "0" "$STATUS"
  assert_contains "$app, distro has it: installs it" "$CALLS" "install $pkg"
  mock_cleanup
done

# Firefox: the distro's own firefox deb where there's no firefox-esr
# (Linux Mint, Pop!_OS), but not Ubuntu's stub that installs the snap.
setup
sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-firefox-esr-install" >"$MOCK_DIR/install"
MOCK_CANDIDATE=firefox run "$MOCK_DIR/install" --skip-prompt
assert_eq "firefox, Mint (no firefox-esr, a firefox deb): exits 0" "0" "$STATUS"
assert_contains "firefox, Mint: installs the distro's own firefox" "$CALLS" "sudo /usr/bin/apt -y install firefox"
assert_not_contains "firefox, Mint: not firefox-esr" "$CALLS" "install firefox-esr"
mock_cleanup

setup
sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-firefox-esr-install" >"$MOCK_DIR/install"
# Enter for "Press Enter", so the question after the install is reached.
OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" MOCK_CANDIDATE=firefox PATH="$(mock_path)" \
  bash "$MOCK_DIR/install" <<<"" >/dev/null 2>&1
assert_contains "firefox, Mint: asks about the default browser for firefox" "$(cat "$MOCK_CALLS")" \
  "ohmydebn-browser-set-default --ask firefox"
mock_cleanup

setup
sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-firefox-esr-install" >"$MOCK_DIR/install"
MOCK_CANDIDATE="firefox-esr firefox" run "$MOCK_DIR/install" --skip-prompt
assert_contains "firefox, both available: firefox-esr" "$CALLS" "sudo /usr/bin/apt -y install firefox-esr"
mock_cleanup

setup
sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-firefox-esr-install" >"$MOCK_DIR/install"
MOCK_SNAP_STUB=firefox run "$MOCK_DIR/install"
assert_eq "firefox, Ubuntu (only the snap stub): exits 1" "1" "$STATUS"
assert_contains "firefox, Ubuntu: points to Install > Package" "$OUT" "choose Install > Package"
assert_not_contains "firefox, Ubuntu: nothing run as root" "$CALLS" "sudo"
mock_cleanup

test_summary
