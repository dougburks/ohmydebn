#!/bin/bash
#
# Unit tests for bin/ohmydebn-aether's launch environment. Aether >= 4.29.9
# applies themes through an `omarchy` executable found on PATH (OhMyDebn's
# shim in /usr/share/ohmydebn/bin); the session normally has that directory
# on PATH via ~/.xsessionrc, but Raspberry Pi OS doesn't source that file,
# and a hotkey launch there reached Aether with no shim in reach. The
# launcher must put it on PATH itself, without duplicating it when it's
# already there, and keep exporting OMARCHY_PATH. The Aether binary is
# patched to a stub that prints its environment.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-aether"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-aether (launch environment) ==="

setup() {
  mock_init
  mock_bin aether <<'EOF2'
#!/bin/bash
echo "PATH=$PATH"
echo "OMARCHY_PATH=$OMARCHY_PATH"
EOF2
  sed "s#/usr/share/aether/aether#$MOCK_BIN/aether#" "$SCRIPT" >"$MOCK_DIR/aether-patched.sh"
}

# --- a session PATH without the bin dir (Raspberry Pi OS): prepended ---
setup
OUT=$(HOME=/home/pi PATH="/usr/local/bin:/usr/bin:/bin" bash "$MOCK_DIR/aether-patched.sh" 2>&1)
assert_contains "bin dir absent: prepended to PATH" "$OUT" "PATH=/usr/share/ohmydebn/bin:/usr/local/bin:/usr/bin:/bin"
assert_contains "OMARCHY_PATH still exported" "$OUT" "OMARCHY_PATH=/home/pi/.local/share/omarchy"
mock_cleanup

# --- already on PATH (the usual Debian session): unchanged, no duplicate ---
setup
OUT=$(HOME=/home/pi PATH="/usr/share/ohmydebn/bin:/usr/bin:/bin" bash "$MOCK_DIR/aether-patched.sh" 2>&1)
assert_contains "bin dir present: PATH left exactly as it was" "$OUT" "PATH=/usr/share/ohmydebn/bin:/usr/bin:/bin"
mock_cleanup

# --- present but not first: still counts as present ---
setup
OUT=$(HOME=/home/pi PATH="/usr/bin:/usr/share/ohmydebn/bin:/bin" bash "$MOCK_DIR/aether-patched.sh" 2>&1)
assert_contains "bin dir in the middle: PATH left as it was" "$OUT" "PATH=/usr/bin:/usr/share/ohmydebn/bin:/bin"
mock_cleanup

test_summary
