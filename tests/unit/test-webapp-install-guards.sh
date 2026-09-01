#!/bin/bash
#
# Unit tests for bin/ohmydebn-webapp-install's guards against desktop-entry
# injection and curl argument injection. APP_NAME/APP_URL are written
# verbatim into a .desktop file whose key=value parser takes the last
# occurrence of a duplicate key, so a newline in either could let an
# attacker inject their own Exec= that silently wins over the real one;
# ICON_URL reaches curl as a bare positional argument, so a leading '-'
# could make curl read it as an option instead of a URL. curl is stubbed
# out so these are exercised without any network access.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-webapp-install"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-webapp-install ==="

setup_mocks() {
  mock_bin curl <<'EOF'
#!/bin/bash
echo "curl $*" >>"$MOCK_CALLS"
touch "$3"
exit 0
EOF
}

install_webapp() {
  : >"$MOCK_CALLS"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$SCRIPT" "$1" "$2" "$3" >/dev/null 2>&1
}

fresh_scratch_home() {
  [[ -n "${SCRATCH_HOME:-}" ]] && rm -rf "$SCRATCH_HOME"
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/share/applications"
}

mock_init
setup_mocks

# --- A newline in APP_NAME or APP_URL could inject an extra Desktop Entry key ---
fresh_scratch_home
install_webapp $'Evil\nExec=touch /tmp/pwned' "https://example.com" "https://example.com/icon.png"
assert_eq "refuses newline in app name" "" "$(cat "$MOCK_CALLS")"
assert_eq "writes no desktop file" "" "$(find "$SCRATCH_HOME/.local/share/applications" -name '*.desktop')"

fresh_scratch_home
install_webapp "Evil" $'https://example.com\nExec=touch /tmp/pwned' "https://example.com/icon.png"
assert_eq "refuses newline in app url" "" "$(cat "$MOCK_CALLS")"

# --- APP_URL must carry a real scheme, not be passed through as-is ---
fresh_scratch_home
install_webapp "Evil" "javascript" "https://example.com/icon.png"
assert_eq "refuses app url without a scheme" "" "$(cat "$MOCK_CALLS")"

# --- A leading '-' in ICON_URL would make curl read it as an option ---
fresh_scratch_home
install_webapp "Good" "https://example.com" "--config=/tmp/evil.conf"
assert_eq "refuses icon url starting with '-'" "" "$(cat "$MOCK_CALLS")"

# --- The ordinary case still works ---
fresh_scratch_home
install_webapp "Good App" "https://example.com" "https://example.com/icon.png"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "downloads the icon after --" "$CALLS" "-- https://example.com/icon.png"
assert_eq "writes the desktop file" "1" "$(find "$SCRATCH_HOME/.local/share/applications" -name '*.desktop' | wc -l)"
DESKTOP_CONTENT=$(cat "$SCRATCH_HOME/.local/share/applications/Good App.desktop")
assert_contains "desktop file has the real Exec" "$DESKTOP_CONTENT" "Exec=ohmydebn-launch-webapp https://example.com"

rm -rf "$SCRATCH_HOME"
mock_cleanup
test_summary
