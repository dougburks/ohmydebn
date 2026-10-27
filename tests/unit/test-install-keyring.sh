#!/bin/bash
#
# Unit tests for install.sh's OhMyDebn repository key step. The key used to
# be piped straight from curl into `gpg --dearmor -o <keyring>`, and gpg
# creates that file even when the download fails - so a network blip on the
# first install left an empty keyring that every rerun skipped (the check was
# -f), and apt failed with NO_PUBKEY until the user deleted it by hand.
#
# SAFETY: as in test-install-assume-yes.sh, OHMYDEBN_TEST_SKIP_CONFIG=1 is
# always set (install.sh would otherwise source the real ohmydebn.sh), sudo
# is a pure logger, and OHMYDEBN_TEST_KEYRING points the keyring at a
# scratch path. curl and gpg are mocked, so nothing touches the network.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install.sh: repository key ==="

OURS=983364A21C37D16AB53B959E7D8932E3EE41B9D1

# setup <curl: ok|fail> [<fingerprint(s) of the served key, space-separated>]
setup() {
  # What the stand-in gpg --show-keys reports for the downloaded key.
  export MOCK_KEY_FPRS="${2:-$OURS}"
  mock_init
  mock_bin dpkg <<'STUB'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn" ]] && exit 0
exit 1
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
exit 0
STUB
  mock_bin clear <<'STUB'
#!/bin/bash
exit 0
STUB
  if [[ "$1" == ok ]]; then
    mock_bin curl <<'STUB'
#!/bin/bash
mock_log "curl $*"
while [[ $# -gt 0 ]]; do
  [[ "$1" == "-o" ]] && echo "-----BEGIN PGP PUBLIC KEY BLOCK-----" >"$2"
  shift
done
STUB
  else
    mock_bin curl <<'STUB'
#!/bin/bash
mock_log "curl $*"
exit 6
STUB
  fi
  # Like the real thing: the output file is created even when the input is
  # empty or missing, and the exit code is non-zero then.
  mock_bin gpg <<'STUB'
#!/bin/bash
OUT="" IN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -o) OUT="$2"; shift ;;
  --homedir) shift ;;
  --dearmor) ;;
  --show-keys) SHOW=1 ;;
  --with-colons) ;;
  *) IN="$1" ;;
  esac
  shift
done
if [[ -n "${SHOW:-}" ]]; then
  # One pub line and its fpr per key, then a subkey's (which isn't a
  # primary key and mustn't be counted).
  for f in $MOCK_KEY_FPRS; do
    echo "pub:u:4096:1:${f: -16}:1763146575:::u:::scESC:"
    echo "fpr:::::::::$f:"
    echo "sub:u:4096:1:022ADEF6938655DE:1763146575::::::e:"
    echo "fpr:::::::::C9F855EEC9E932FF90304026022ADEF6938655DE:"
  done
  exit 0
fi
: >"$OUT"
if [[ -s "$IN" ]]; then
  echo key >"$OUT"
else
  exit 2
fi
STUB
  printf 'ID=debian\nVERSION_CODENAME=trixie\n' >"$MOCK_DIR/os-release"
  KEYRING="$MOCK_DIR/keyring.gpg"
}

run() {
  OUTPUT=$(HOME="$MOCK_DIR" OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" \
    OHMYDEBN_TEST_SKIP_CONFIG=1 OHMYDEBN_TEST_KEYRING="$KEYRING" PATH="$(mock_path)" \
    bash "$SCRIPT" --yes </dev/null 2>&1)
  EXIT_CODE=$?
}

# Download fails: the run stops with a clear message, and nothing (in
# particular no empty keyring) is installed.
setup fail
run
assert_eq "download fails: install stops" "1" "$EXIT_CODE"
assert_contains "download fails: says why" "$OUTPUT" "Couldn't download the OhMyDebn repository key"
assert_not_contains "download fails: no keyring installed" "$(cat "$MOCK_CALLS")" "sudo install"
mock_cleanup

# Download works: the dearmored key is installed at the keyring path.
setup ok
run
assert_eq "download works: install continues" "0" "$EXIT_CODE"
assert_contains "download works: keyring installed" "$(cat "$MOCK_CALLS")" "sudo install -m 644"
assert_contains "download works: at the keyring path" "$(cat "$MOCK_CALLS")" "$KEYRING"
mock_cleanup

# A key that isn't OhMyDebn's, or OhMyDebn's with another added: refused,
# nothing installed.
setup ok 47D32A74E9A9E013A4B4926C68D513D36A73CD96
run
assert_eq "someone else's key: install stops" "1" "$EXIT_CODE"
assert_contains "someone else's key: says why" "$OUTPUT" "isn't OhMyDebn's, so it wasn't installed"
assert_not_contains "someone else's key: no keyring installed" "$(cat "$MOCK_CALLS")" "sudo install"
mock_cleanup

setup ok "$OURS 47D32A74E9A9E013A4B4926C68D513D36A73CD96"
run
assert_eq "OhMyDebn's key plus another: install stops" "1" "$EXIT_CODE"
assert_not_contains "OhMyDebn's key plus another: no keyring installed" "$(cat "$MOCK_CALLS")" "sudo install"
mock_cleanup

# An empty keyring left by an earlier failed run is replaced, not skipped.
setup ok
: >"$KEYRING"
run
assert_contains "empty keyring from an earlier run: downloaded again" "$(cat "$MOCK_CALLS")" "curl -fsSL"
assert_contains "empty keyring from an earlier run: replaced" "$(cat "$MOCK_CALLS")" "sudo install -m 644"
mock_cleanup

# A real keyring is left alone: no download at all.
setup ok
echo key >"$KEYRING"
run
assert_not_contains "existing keyring: not downloaded again" "$(cat "$MOCK_CALLS")" "curl -fsSL"
mock_cleanup

test_summary
