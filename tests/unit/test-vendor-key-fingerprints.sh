#!/bin/bash
#
# Unit tests for the signing-key checks in the Antigravity, Cloudflare
# WARP, Helium and Tailscale installers. Each used to hand whatever key its
# vendor's URL served straight to apt, so a key swapped in transit or on
# the vendor's server was trusted for every package from that repo. Now
# the key is checked against the vendor's fingerprint first, and a
# mismatch stops the install before anything is written. Tailscale's apt
# source, which was downloaded too, is written by the installer itself.
#
# /etc/apt, /usr/share/keyrings and /usr/share/ohmydebn are sed-patched to
# a scratch root; sudo runs its command for real against those paths
# except apt and tailscale, which are only logged; curl writes the
# vendor's real public key from tests/lib (or MOCK_KEY: another vendor's,
# or MOCK_CURL_FAILS: none); gpg --dearmor copies its input. The
# fingerprint check is the real one.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== vendor signing keys: antigravity, cloudflare-warp, helium-bin, tailscale installers ==="

# One scratch root for every case (setup empties it), so the paths each
# case checks can be worked out before its setup runs.
MOCK_ROOT=$(mktemp -d)
trap 'rm -rf "$MOCK_ROOT"' EXIT

setup() {
  mock_init
  ROOT="$MOCK_ROOT"
  rm -rf "${ROOT:?}"/*
  BIN="$ROOT/usr/share/ohmydebn/bin"
  mkdir -p "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/preferences.d" "$BIN" \
    "$ROOT/usr/share/ohmydebn/config/net.imput.helium" "$MOCK_DIR/home/.config"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$1" == /usr/bin/apt || "$1" == /usr/bin/tailscale ]] && exit 0
exec "$@"
EOF2
  mock_bin curl <<'EOF2'
#!/bin/bash
# curl -fsSL <url> -o <dest>
mock_log "curl $*"
[ -n "${MOCK_CURL_FAILS:-}" ] && exit 22
cp "$REPO_ROOT/tests/lib/$MOCK_KEY" "${!#}"
EOF2
  # gpg --dearmor [--yes] -o|--output <dest> <src>
  mock_bin gpg <<'EOF2'
#!/bin/bash
mock_log "gpg $*"
while [ $# -gt 1 ]; do
  case "$1" in -o | --output) dest="$2"; shift ;; esac
  shift
done
cp "$1" "$dest"
EOF2
  cp "$REPO_ROOT/bin/ohmydebn-pgp-fingerprint" "$BIN/"
  for stub in ohmydebn-ai-set-default ohmydebn-browser-set-default; do
    printf '#!/bin/bash\nexit 0\n' >"$BIN/$stub"
    chmod +x "$BIN/$stub"
  done
  printf '%s\n' "ID=debian" "VERSION_CODENAME=trixie" >"$MOCK_DIR/os-release"
}

# run_installer <installer name>: MOCK_KEY names the key curl serves.
run_installer() {
  sed -e "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g" \
    -e "s#/usr/share/keyrings#$ROOT/usr/share/keyrings#g" \
    -e "s#/etc/apt#$ROOT/etc/apt#g" \
    "$REPO_ROOT/bin/$1" >"$MOCK_DIR/installer"
  OUTPUT=$(HOME="$MOCK_DIR/home" REPO_ROOT="$REPO_ROOT" MOCK_KEY="$MOCK_KEY" \
    OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" PATH="$(mock_path)" \
    bash "$MOCK_DIR/installer" <<<"" 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

exists() { [[ -e "$1" ]] && echo yes || echo no; }

# check_vendor <label> <installer> <its key fixture> <keyring> <source> <pin> <package>
check_vendor() {
  local label="$1" installer="$2" key="$3" keyring="$MOCK_ROOT$4" source="$MOCK_ROOT$5" pin="$MOCK_ROOT$6" package="$7"

  setup
  MOCK_KEY="$key" run_installer "$installer"
  assert_eq "$label, the vendor's key: installs" "0" "$STATUS"
  assert_eq "$label, the vendor's key: the keyring holds it" "$(sha256sum <"$REPO_ROOT/tests/lib/$key")" \
    "$(sha256sum <"$keyring" 2>/dev/null)"
  assert_eq "$label, the vendor's key: the source is written" "yes" "$(exists "$source")"
  assert_contains "$label, the vendor's key: installs $package" "$CALLS" "apt -y install $package"
  mock_cleanup

  setup
  MOCK_KEY=anthropic-signing-key.asc run_installer "$installer"
  assert_eq "$label, another key: fails" "1" "$STATUS"
  assert_contains "$label, another key: says why" "$OUTPUT" "so it wasn't installed"
  assert_eq "$label, another key: no keyring" "no" "$(exists "$keyring")"
  assert_eq "$label, another key: no source" "no" "$(exists "$source")"
  assert_eq "$label, another key: no pin" "no" "$(exists "$pin")"
  assert_not_contains "$label, another key: apt not run" "$CALLS" "/usr/bin/apt"
  mock_cleanup

  setup
  MOCK_CURL_FAILS=1 MOCK_KEY="$key" run_installer "$installer"
  assert_eq "$label, download fails: stops" "1" "$([ "$STATUS" -ne 0 ] && echo 1 || echo 0)"
  assert_eq "$label, download fails: no keyring" "no" "$(exists "$keyring")"
  assert_eq "$label, download fails: no source" "no" "$(exists "$source")"
  mock_cleanup
}

check_vendor "Antigravity" ohmydebn-antigravity-install google-artifact-registry-signing-key.asc \
  /etc/apt/keyrings/antigravity-repo-key.gpg /etc/apt/sources.list.d/antigravity.list \
  /etc/apt/preferences.d/antigravity.pref antigravity
check_vendor "Cloudflare WARP" ohmydebn-cloudflare-warp-install cloudflare-signing-key.asc \
  /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg /etc/apt/sources.list.d/cloudflare-client.list \
  /etc/apt/preferences.d/cloudflare-client.pref cloudflare-warp
check_vendor "Helium" ohmydebn-helium-bin-install helium-signing-key.asc \
  /usr/share/keyrings/helium.gpg /etc/apt/sources.list.d/helium.list \
  /etc/apt/preferences.d/helium.pref helium-bin
check_vendor "Tailscale" ohmydebn-tailscale-install tailscale-signing-key.gpg \
  /usr/share/keyrings/tailscale-archive-keyring.gpg /etc/apt/sources.list.d/tailscale.list \
  /etc/apt/preferences.d/tailscale.pref tailscale

# Tailscale's source is written here, not downloaded: only the key is
# fetched, and the line is the one Tailscale's own .list file holds.
setup
MOCK_KEY=tailscale-signing-key.gpg run_installer ohmydebn-tailscale-install
assert_eq "Tailscale: only the key is downloaded" "1" "$(grep -c '^curl ' "$MOCK_CALLS")"
assert_eq "Tailscale: the source line" \
  "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian trixie main" \
  "$(sed "s#$ROOT##" "$ROOT/etc/apt/sources.list.d/tailscale.list")"
mock_cleanup

test_summary
