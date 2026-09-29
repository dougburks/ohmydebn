#!/bin/bash
#
# Unit tests for bin/ohmydebn-cloudflare-warp-install. Cloudflare's repo
# serves Debian and Ubuntu release names only (trixie, noble, resolute...),
# but the installer used `lsb_release -cs`, which on Kali, Mint, LMDE,
# Devuan and LCOS is the derivative's own codename (kali-rolling, zena,
# gigi, excalibur). apt update then failed, and the source it had written
# stayed behind, failing every later apt update and ohmydebn-update. Each
# supported distro's os-release (the same values the distro-detection tests
# use) must get a codename Cloudflare serves, and a source apt can't
# refresh must be removed again. sudo, apt, curl and gpg are mocked, and
# the system paths point into a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-cloudflare-warp-install ==="

setup() {
  mock_init
  ROOT="$MOCK_DIR/root"
  mkdir -p "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/preferences.d"
  mock_bin sudo <<'EOF2'
#!/bin/bash
exec "$@"
EOF2
  mock_bin dpkg <<'EOF2'
#!/bin/bash
exit 1
EOF2
  mock_bin curl <<'EOF2'
#!/bin/bash
echo "key"
EOF2
  mock_bin gpg <<'EOF2'
#!/bin/bash
while [ $# -gt 0 ]; do [ "$1" = --output ] && { cat >"$2"; exit 0; }; shift; done
EOF2
  # What lsb_release -cs really prints: the distro's own codename.
  mock_bin lsb_release <<'EOF2'
#!/bin/bash
. "$OHMYDEBN_TEST_OS_RELEASE"
echo "$VERSION_CODENAME"
EOF2
  mock_bin apt <<'EOF2'
#!/bin/bash
mock_log "apt $*"
[ "$1" = update ] && exit "${MOCK_APT_UPDATE_EXIT:-0}"
exit 0
EOF2
  sed -e "s#/usr/share/keyrings#$ROOT/usr/share/keyrings#g" -e "s#/etc/apt#$ROOT/etc/apt#g" \
    -e "s#/usr/bin/apt#$MOCK_BIN/apt#g" \
    "$REPO_ROOT/bin/ohmydebn-cloudflare-warp-install" >"$MOCK_DIR/warp-install.sh"
}

# run_install <os-release line>...
run_install() {
  printf '%s\n' "$@" >"$MOCK_DIR/os-release"
  OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" PATH="$(mock_path)" \
    bash "$MOCK_DIR/warp-install.sh" <<<"" >"$MOCK_DIR/out" 2>&1
}

codename_in_list() {
  sed -n 's#.*pkg.cloudflareclient.com/ \([^ ]*\) main#\1#p' "$ROOT/etc/apt/sources.list.d/cloudflare-client.list"
}

# expect <label> <codename> <os-release line>...
expect() {
  local label="$1" want="$2"
  shift 2
  setup
  run_install "$@"
  assert_eq "$label: uses $want" "$want" "$(codename_in_list)"
  mock_cleanup
}

expect "Debian 13" trixie "ID=debian" "VERSION_CODENAME=trixie"
expect "MX Linux 25" trixie "ID=debian" "VERSION_CODENAME=trixie" 'VERSION_ID="13"'
expect "LMDE 7" trixie "ID=linuxmint" "VERSION_CODENAME=gigi" "DEBIAN_CODENAME=trixie"
expect "Kali" trixie "ID=kali" "VERSION_CODENAME=kali-rolling" "ID_LIKE=debian"
expect "Devuan 6" trixie "ID=devuan" "ID_LIKE=debian" "VERSION_CODENAME=excalibur"
expect "LCOS" trixie "ID=lcos" 'ID_LIKE="devuan debian"' "VERSION_CODENAME=excalibur"
expect "Mint 22.3" noble "ID=linuxmint" "VERSION_CODENAME=zena" "UBUNTU_CODENAME=noble"
expect "Pop!_OS 24.04" noble "ID=pop" 'ID_LIKE="ubuntu debian"' "VERSION_CODENAME=noble" "UBUNTU_CODENAME=noble"
expect "Ubuntu 24.04" noble "ID=ubuntu" "VERSION_CODENAME=noble" "UBUNTU_CODENAME=noble"
expect "Ubuntu 26.04 (no UBUNTU_CODENAME)" resolute "ID=ubuntu" "VERSION_CODENAME=resolute"

# --- apt update fails: the source, pin and key are taken back out ---
setup
MOCK_APT_UPDATE_EXIT=100 run_install "ID=kali" "VERSION_CODENAME=kali-rolling"
assert_eq "apt update fails: the source is removed again" "no" \
  "$([[ -e $ROOT/etc/apt/sources.list.d/cloudflare-client.list ]] && echo yes || echo no)"
assert_eq "apt update fails: the pin is removed again" "no" \
  "$([[ -e $ROOT/etc/apt/preferences.d/cloudflare-client.pref ]] && echo yes || echo no)"
assert_eq "apt update fails: the key is removed again" "no" \
  "$([[ -e $ROOT/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg ]] && echo yes || echo no)"
assert_not_contains "apt update fails: nothing is installed" "$(cat "$MOCK_CALLS")" "install cloudflare-warp"
assert_contains "apt update fails: says what happened" "$(cat "$MOCK_DIR/out")" "package source was removed again"
mock_cleanup

# --- apt update works: installed, source and pin kept ---
setup
run_install "ID=debian" "VERSION_CODENAME=trixie"
assert_contains "installs cloudflare-warp" "$(cat "$MOCK_CALLS")" "apt -y install cloudflare-warp"
assert_eq "keeps the pin" "yes" "$([[ -f $ROOT/etc/apt/preferences.d/cloudflare-client.pref ]] && echo yes || echo no)"
mock_cleanup

test_summary
