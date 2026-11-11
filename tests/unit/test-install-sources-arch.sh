#!/bin/bash
#
# Unit tests for the Architectures line in OhMyDebn's apt source, written
# by install.sh. Without it apt asked OhMyDebn's repo for every
# architecture dpkg had turned on, and where i386 is on as well (MX Linux
# and LMDE by default) every apt update printed a notice that the repo
# doesn't support i386. New installs get the line in the file; existing
# ones get it inserted once, guarded by a machine-wide marker.
#
# SAFETY: as in test-install-assume-yes.sh, OHMYDEBN_TEST_SKIP_CONFIG=1 is
# always set. The sources file, the marker directory, the apt directory
# and the keyring are scratch paths; sudo runs a command for real only
# when it names a path under the scratch directory, and otherwise (apt,
# chronyc) only logs it. dpkg answers the architecture from MOCK_ARCH.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install.sh: OhMyDebn apt source's Architectures line ==="

setup() {
  mock_init
  mock_bin dpkg <<'STUB'
#!/bin/bash
[[ "$1" == "--print-architecture" ]] && { echo "${MOCK_ARCH:-amd64}"; exit 0; }
[[ "$1" == "-s" && "$2" == "ohmydebn" ]] && exit 0
exit 1
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
case "$*" in
*"$MOCK_DIR"*) exec "$@" ;;
esac
exit 0
STUB
  mock_bin clear <<'STUB'
#!/bin/bash
exit 0
STUB
  printf 'ID=debian\nVERSION_CODENAME=trixie\n' >"$MOCK_DIR/os-release"
  mkdir -p "$MOCK_DIR/apt/sources.list.d" "$MOCK_DIR/state"
  : >"$MOCK_DIR/apt/sources.list.d/debian.sources"
  echo key >"$MOCK_DIR/keyring.gpg"
  SOURCES="$MOCK_DIR/apt/sources.list.d/ohmydebn.sources"
  MARKER="$MOCK_DIR/state/ohmydebn-sources-architectures"
}
run() {
  HOME="$MOCK_DIR" MOCK_ARCH="${MOCK_ARCH:-amd64}" \
    OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" OHMYDEBN_TEST_SKIP_CONFIG=1 \
    OHMYDEBN_TEST_APT_DIR="$MOCK_DIR/apt" OHMYDEBN_TEST_KEYRING="$MOCK_DIR/keyring.gpg" \
    OHMYDEBN_TEST_OHMYDEBN_SOURCES="$SOURCES" OHMYDEBN_TEST_SYSTEM_STATE_DIR="$MOCK_DIR/state" \
    PATH="$(mock_path)" bash "$SCRIPT" --yes </dev/null >/dev/null 2>&1
  EXIT_CODE=$?
}

# An install from before the line, as install.sh wrote it then, with a
# trailing blank line (an editor's, say): an appended field would start a
# second stanza there.
OLD='Types: deb
URIs: https://packages.ohmydebn.org/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/ohmydebn-keyring.gpg
'

setup
run
assert_eq "new install: runs" "0" "$EXIT_CODE"
assert_eq "new install: the line is in the new file" "Architectures: amd64" "$(grep '^Architectures:' "$SOURCES")"
assert_eq "new install: marker written" "yes" "$([ -f "$MARKER" ] && echo yes || echo no)"
mock_cleanup

setup
MOCK_ARCH=arm64 run
assert_eq "new install, arm64 (Raspberry Pi OS): its own architecture" "Architectures: arm64" "$(grep '^Architectures:' "$SOURCES")"
mock_cleanup

setup
printf '%s\n' "$OLD" >"$SOURCES"
run
assert_eq "existing install: runs" "0" "$EXIT_CODE"
assert_eq "existing install: the line inserted right after URIs" "URIs: https://packages.ohmydebn.org/
Architectures: amd64
Suites: trixie" "$(sed -n 2,4p "$SOURCES")"
assert_eq "existing install: still one stanza (no blank line inside)" "0" \
  "$(sed '/^Architectures:/q' "$SOURCES" | grep -c '^$')"
assert_eq "existing install: marker written" "yes" "$([ -f "$MARKER" ] && echo yes || echo no)"
run
assert_eq "rerun: still one line" "1" "$(grep -c '^Architectures:' "$SOURCES")"
mock_cleanup

setup
printf '%s\n' "$OLD" | sed 's#packages.ohmydebn.org#packages-testing.ohmydebn.org#' >"$SOURCES"
run
assert_eq "testing channel: the line inserted too" "Architectures: amd64" "$(grep '^Architectures:' "$SOURCES")"
assert_contains "testing channel: its URIs kept" "$(cat "$SOURCES")" "URIs: https://packages-testing.ohmydebn.org/"
mock_cleanup

setup
printf '%s\n' "$OLD" | sed '2a Architectures: amd64 arm64' >"$SOURCES"
run
assert_eq "line already there: left as it is" "Architectures: amd64 arm64" "$(grep '^Architectures:' "$SOURCES")"
mock_cleanup

setup
printf '%s\n' "$OLD" >"$SOURCES"
touch "$MARKER"
run
assert_eq "marker there (the user took the line out): not added back" "0" "$(grep -c '^Architectures:' "$SOURCES")"
mock_cleanup

test_summary
