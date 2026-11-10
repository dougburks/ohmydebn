#!/bin/bash
#
# Unit tests for bin/ohmydebn-firewall-hint. ufw is in /usr/sbin, which a
# normal user's PATH leaves out on Debian, so `command -v ufw` alone never
# found it there and the SSH and Remote Desktop server windows never said
# the firewall was blocking them. SBIN_DIRS points at a mock sbin folder,
# and PATH is set explicitly, without sbin, so the machine running the
# tests doesn't matter.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-firewall-hint ==="

setup() {
  mock_init
  mkdir -p "$MOCK_DIR/sbin"
  sed "s#^SBIN_DIRS=.*#SBIN_DIRS=$MOCK_DIR/sbin#" "$REPO_ROOT/bin/ohmydebn-firewall-hint" >"$MOCK_DIR/hint"
  # sudo ufw status prints MOCK_UFW_STATUS.
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
printf '%s\n' "$MOCK_UFW_STATUS"
STUB
}
# A ufw in the mock sbin folder only, off PATH, as on Debian.
ufw_in_sbin() {
  printf '#!/bin/bash\nexit 0\n' >"$MOCK_DIR/sbin/ufw"
  chmod +x "$MOCK_DIR/sbin/ufw"
}
run() {
  OUT=$(PATH="$MOCK_BIN:/usr/bin:/bin" bash "$MOCK_DIR/hint" 22 "SSH Server" </dev/null 2>&1)
  STATUS=$?
}

setup
ufw_in_sbin
MOCK_UFW_STATUS=$'Status: active\n\nTo                         Action      From\n--                         ------      ----' run
assert_eq "ufw only in sbin: exits 0" "0" "$STATUS"
assert_contains "ufw only in sbin: still finds it and says the port is closed" "$OUT" "no rule allows port 22 yet"
assert_contains "ufw only in sbin: with the allow commands" "$OUT" "sudo ufw allow 22/tcp"
mock_cleanup

setup
ufw_in_sbin
MOCK_UFW_STATUS="Status: inactive" run
assert_contains "ufw only in sbin, inactive: says the port is reachable" "$OUT" "The firewall is inactive, so port 22 is reachable."
mock_cleanup

setup
MOCK_UFW_STATUS="Status: active" run
assert_eq "no ufw: exits 0" "0" "$STATUS"
assert_eq "no ufw: says nothing" "" "$OUT"
mock_cleanup

test_summary
