#!/bin/bash
#
# Unit tests for bin/ohmydebn-powershell-repo, the PowerShell install and
# remove scripts built on it, and the update's move off Microsoft's
# packages-microsoft-prod.deb (install/packaging/powershell-repo.sh). The
# setup package used to be installed unchecked, running its scripts as
# root; now only a key matching Microsoft's published fingerprint is
# written, alongside our own sources file and pin.
#
# /etc/apt, /usr/share/keyrings and /usr/share/ohmydebn are sed-patched to
# a scratch root; sudo runs its command for real against those paths
# except apt, which is only logged; curl writes Microsoft's real key (or
# MOCK_KEY=anthropic: someone else's); dpkg answers from MOCK_INSTALLED.
# The fingerprint check is the real one.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-powershell-repo / -install / -remove / install/packaging/powershell-repo.sh ==="

setup() {
  mock_init
  ROOT="$MOCK_DIR/root"
  BIN="$ROOT/usr/share/ohmydebn/bin"
  mkdir -p "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/preferences.d" "$ROOT/usr/share/keyrings" "$BIN"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$1" == /usr/bin/apt ]] && exit 0
exec "$@"
EOF2
  mock_bin curl <<'EOF2'
#!/bin/bash
# curl -fsSL <url> -o <dest>
mock_log "curl $*"
cp "$MOCK_DIR/${MOCK_KEY:-microsoft}.asc" "${!#}"
EOF2
  cp "$REPO_ROOT/tests/lib/microsoft-signing-key.asc" "$MOCK_DIR/microsoft.asc"
  cp "$REPO_ROOT/tests/lib/anthropic-signing-key.asc" "$MOCK_DIR/anthropic.asc"
  cp "$REPO_ROOT/bin/ohmydebn-pgp-fingerprint" "$BIN/"
  printf '#!/bin/bash\necho "== $*"\n' >"$BIN/ohmydebn-headline"
  chmod +x "$BIN/ohmydebn-headline"
  for script in ohmydebn-powershell-repo ohmydebn-powershell-install ohmydebn-powershell-remove; do
    sed "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g; s#^APT_ETC=/etc/apt#APT_ETC=$ROOT/etc/apt#; s#^KEYRING=/usr/share/keyrings#KEYRING=$ROOT/usr/share/keyrings#" \
      "$REPO_ROOT/bin/$script" >"$BIN/$script"
    chmod +x "$BIN/$script"
  done
  sed "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g" "$REPO_ROOT/install/packaging/powershell-repo.sh" >"$MOCK_DIR/migrate.sh"
  KEY="$ROOT/usr/share/keyrings/microsoft-prod.asc"
  LIST="$ROOT/etc/apt/sources.list.d/microsoft-prod.list"
  PREF="$ROOT/etc/apt/preferences.d/powershell.pref"
}
# The installer reads one Enter.
run() { PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" bash "$@" <<<""; }
migrate() { PATH="$(mock_path)" OHMYDEBN_TEST_APT_DIR="$ROOT/etc/apt" bash "$MOCK_DIR/migrate.sh" </dev/null; }
there() { [ -e "$1" ] && echo yes || echo no; }
# An install from before 4.12.0: Microsoft's setup package's list and key,
# and OhMyDebn's pin.
old_install() {
  echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/13/prod trixie main" >"$LIST"
  : >"$PREF"
}

# --- fresh install: Microsoft's key, our sources file and pin; no setup package ---
setup
OUT=$(run "$BIN/ohmydebn-powershell-install" 2>&1)
STATUS=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "fresh: succeeds" "0" "$STATUS"
assert_eq "fresh: Microsoft's key installed, as published" "yes" "$(cmp -s "$KEY" "$REPO_ROOT/tests/lib/microsoft-signing-key.asc" && echo yes || echo no)"
assert_eq "fresh: the Debian 13 repo, signed by that key" \
  "deb [arch=amd64,arm64,armhf signed-by=$KEY] https://packages.microsoft.com/debian/13/prod trixie main" "$(cat "$LIST")"
assert_contains "fresh: pinned to PowerShell" "$(cat "$PREF")" "Package: powershell"
assert_contains "fresh: the rest of the repo is blocked" "$(cat "$PREF")" "Pin-Priority: -1"
assert_contains "fresh: PowerShell installed" "$CALLS" "sudo /usr/bin/apt -y install powershell"
assert_not_contains "fresh: Microsoft's setup package never downloaded" "$CALLS" "packages-microsoft-prod"
assert_not_contains "fresh: no setup package to purge" "$CALLS" "purge"
mock_cleanup

# --- a key that isn't Microsoft's: refused, nothing written or installed ---
setup
OUT=$(MOCK_KEY=anthropic run "$BIN/ohmydebn-powershell-install" 2>&1)
STATUS=$?
assert_eq "wrong key: fails" "1" "$STATUS"
assert_contains "wrong key: says why" "$OUT" "isn't the one Microsoft publishes, so it wasn't installed"
assert_eq "wrong key: no key written" "no" "$(there "$KEY")"
assert_eq "wrong key: no sources file" "no" "$(there "$LIST")"
assert_eq "wrong key: no pin" "no" "$(there "$PREF")"
assert_not_contains "wrong key: nothing installed" "$(cat "$MOCK_CALLS")" "apt -y install"
mock_cleanup

# --- update of an older install: the setup package is replaced by ours ---
setup
old_install
OUT=$(MOCK_INSTALLED="powershell packages-microsoft-prod" migrate 2>&1)
STATUS=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "migrate: succeeds" "0" "$STATUS"
assert_contains "migrate: says what it's doing" "$OUT" "Moving PowerShell to a checked Microsoft repository setup"
assert_contains "migrate: purges Microsoft's setup package" "$CALLS" "sudo /usr/bin/apt -y purge packages-microsoft-prod"
assert_eq "migrate: our key installed" "yes" "$(cmp -s "$KEY" "$REPO_ROOT/tests/lib/microsoft-signing-key.asc" && echo yes || echo no)"
assert_contains "migrate: the sources file names our key" "$(cat "$LIST")" "signed-by=$KEY]"
assert_contains "migrate: pin kept" "$(cat "$PREF")" "Package: powershell"
assert_not_contains "migrate: PowerShell itself isn't touched" "$CALLS" "purge powershell"
mock_cleanup

# --- the key check fails during the update: nothing changes, the update goes on ---
setup
old_install
OUT=$(MOCK_KEY=anthropic MOCK_INSTALLED="powershell packages-microsoft-prod" migrate 2>&1)
STATUS=$?
assert_eq "migrate, wrong key: the update isn't stopped" "0" "$STATUS"
assert_contains "migrate, wrong key: says it'll retry" "$OUT" "PowerShell's repository setup wasn't changed. The next update will try again."
assert_not_contains "migrate, wrong key: the setup package stays" "$(cat "$MOCK_CALLS")" "purge"
assert_contains "migrate, wrong key: Microsoft's sources file untouched" "$(cat "$LIST")" "signed-by=/usr/share/keyrings/microsoft-prod.gpg]"
mock_cleanup

# --- already moved, or never OhMyDebn's: nothing to do ---
setup
old_install
OUT=$(MOCK_INSTALLED="powershell" migrate 2>&1)
assert_eq "already moved: nothing run" "" "$(cat "$MOCK_CALLS")"
assert_eq "already moved: nothing said" "" "$OUT"
mock_cleanup

setup
echo "deb [signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/13/prod trixie main" >"$LIST"
OUT=$(MOCK_INSTALLED="packages-microsoft-prod" migrate 2>&1)
assert_eq "setup package without PowerShell: not OhMyDebn's, left alone" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

setup
echo "deb [signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/13/prod trixie main" >"$LIST"
OUT=$(MOCK_INSTALLED="powershell packages-microsoft-prod" migrate 2>&1)
assert_eq "no OhMyDebn pin: PowerShell installed some other way, left alone" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- remove: our files go, and only an installed setup package is purged ---
setup
MOCK_INSTALLED="" run "$BIN/ohmydebn-powershell-install" >/dev/null 2>&1
: >"$MOCK_CALLS"
OUT=$(MOCK_INSTALLED="powershell" run "$BIN/ohmydebn-powershell-remove" --skip-prompt 2>&1)
STATUS=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "remove: succeeds" "0" "$STATUS"
assert_eq "remove: key gone" "no" "$(there "$KEY")"
assert_eq "remove: sources file gone" "no" "$(there "$LIST")"
assert_eq "remove: pin gone" "no" "$(there "$PREF")"
assert_contains "remove: PowerShell purged" "$CALLS" "sudo /usr/bin/apt -y purge powershell"
assert_not_contains "remove: no setup package named once it's gone" "$CALLS" "packages-microsoft-prod"
mock_cleanup

setup
old_install
OUT=$(MOCK_INSTALLED="powershell packages-microsoft-prod" run "$BIN/ohmydebn-powershell-remove" --skip-prompt 2>&1)
assert_contains "remove, not yet moved: the setup package is purged too" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y purge packages-microsoft-prod"
mock_cleanup

test_summary
