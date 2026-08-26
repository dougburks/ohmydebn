#!/bin/bash
#
# Unit tests for bin/ohmydebn-browser (Super+B's target). It must prefer
# the desktop-wide default browser (xdg-settings + gtk-launch, since
# xdg-open needs a URL and can't be used bare), then fall back through
# x-www-browser and sensible-browser, and finally fail loudly rather than
# silently doing nothing the way the old hardcoded gnome-www-browser target
# did once that alternative went unset.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BROWSER_SCRIPT="$REPO_ROOT/bin/ohmydebn-browser"
BASH_BIN="$(command -v bash)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-browser ==="

mock_init

# Isolated PATH (no real system PATH) so tests are deterministic regardless
# of what's actually installed on the machine running them. bash itself is
# invoked by absolute path so the restricted PATH only affects the script's
# own `command -v` lookups, not finding bash itself.
run_browser() {
  : >"$MOCK_CALLS"
  PATH="$MOCK_BIN" "$BASH_BIN" "$BROWSER_SCRIPT" >"$MOCK_DIR/out" 2>&1
  echo $?
}

# --- xdg-settings + gtk-launch both present and gtk-launch succeeds: used, nothing else called ---
mock_bin xdg-settings <<'EOF'
#!/bin/bash
echo "firefox.desktop"
EOF
mock_bin gtk-launch <<'EOF'
#!/bin/bash
echo "gtk-launch $*" >>"$MOCK_CALLS"
exit 0
EOF
mock_bin x-www-browser <<'EOF'
#!/bin/bash
echo "x-www-browser $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_eq "default browser path: exits 0" "0" "$status"
assert_contains "default browser path: calls gtk-launch with the desktop id" "$(cat "$MOCK_CALLS")" "gtk-launch firefox.desktop"
assert_eq "default browser path: does not fall back to x-www-browser" "" "$(cat "$MOCK_CALLS" | grep x-www-browser || true)"

# --- xdg-settings returns empty (no default set): falls back to x-www-browser ---
mock_bin xdg-settings <<'EOF'
#!/bin/bash
echo ""
EOF
mock_bin gtk-launch <<'EOF'
#!/bin/bash
echo "gtk-launch $*" >>"$MOCK_CALLS"
exit 0
EOF
mock_bin x-www-browser <<'EOF'
#!/bin/bash
echo "x-www-browser $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_contains "empty xdg-settings result: falls back to x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- gtk-launch fails (e.g. stale/uninstalled desktop id): falls back to x-www-browser ---
mock_bin xdg-settings <<'EOF'
#!/bin/bash
echo "stale-browser.desktop"
EOF
mock_bin gtk-launch <<'EOF'
#!/bin/bash
echo "gtk-launch $*" >>"$MOCK_CALLS"
exit 1
EOF
mock_bin x-www-browser <<'EOF'
#!/bin/bash
echo "x-www-browser $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_contains "gtk-launch failure: falls back to x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- xdg-settings/gtk-launch both missing entirely: goes straight to x-www-browser ---
rm -f "$MOCK_BIN/xdg-settings" "$MOCK_BIN/gtk-launch"
mock_bin x-www-browser <<'EOF'
#!/bin/bash
echo "x-www-browser $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_contains "no xdg tooling: uses x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- Only sensible-browser available: used as last resort ---
rm -f "$MOCK_BIN/x-www-browser"
mock_bin sensible-browser <<'EOF'
#!/bin/bash
echo "sensible-browser $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_contains "only sensible-browser available: used" "$(cat "$MOCK_CALLS")" "sensible-browser"

# --- Nothing available at all: fails with a notification instead of silently doing nothing ---
rm -f "$MOCK_BIN/sensible-browser"
mock_bin notify-send <<'EOF'
#!/bin/bash
echo "notify-send $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_eq "nothing available: exits non-zero" "1" "$status"
assert_contains "nothing available: notifies the user" "$(cat "$MOCK_CALLS")" "notify-send"

mock_cleanup
test_summary
