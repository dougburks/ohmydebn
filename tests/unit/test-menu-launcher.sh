#!/bin/bash
#
# Unit tests for install/config/menu.sh: writes the OhMyDebn Menu launcher
# with the ohmydebn-menu-symbolic icon, moves launchers written before
# 4.12.0 off stock_smiley-1 (an icon LMDE 7 doesn't install) without
# touching an icon the user chose, and runs ohmydebn-theme-set-menu-icon so
# an update matches the icons to the current theme.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/menu.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/menu.sh ==="

mock_init
mock_bin ohmydebn-theme-set-menu-icon <<'EOF'
#!/bin/bash
mock_log "ohmydebn-theme-set-menu-icon $*"
EOF
sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/menu-patched.sh"

run_menu_sh() {
  HOME="$SCRATCH_HOME" bash "$MOCK_DIR/menu-patched.sh" </dev/null >/dev/null 2>&1
}

# The launcher as menu.sh wrote it before 4.12.0.
write_old_launcher() { # icon
  mkdir -p "$SCRATCH_HOME/.local/share/applications"
  cat >"$LAUNCHER" <<EOF
[Desktop Entry]
Version=1.0
Name=OhMyDebn Menu
Comment=OhMyDebn Menu
Exec=/usr/share/ohmydebn/bin/ohmydebn-menu
Terminal=false
Type=Application
Icon=$1
StartupNotify=true
EOF
}

# Every icon the launcher or the theme hook names must be one the package
# installs into hicolor.
BUILD="$(cat "$REPO_ROOT/../ohmydebn-package-build/build-package-ohmydebn.sh" 2>/dev/null)"
for icon in ohmydebn-menu-symbolic ohmydebn-menu-outline-symbolic ohmydebn; do
  assert_eq "$icon.svg ships in config/icons" "yes" \
    "$([ -f "$REPO_ROOT/config/icons/$icon.svg" ] && echo yes || echo no)"
  assert_contains "package build installs $icon into hicolor" "$BUILD" \
    "config/icons/$icon.svg\"=/usr/share/icons/hicolor/scalable/apps/$icon.svg"
done

# Scenario 1: new install - the launcher is written with the new icon, and
# the theme hook runs.
SCRATCH_HOME=$(mktemp -d)
LAUNCHER="$SCRATCH_HOME/.local/share/applications/ohmydebn-menu.desktop"
run_menu_sh
assert_contains "new install: launcher uses the symbolic icon" "$(cat "$LAUNCHER")" "Icon=ohmydebn-menu-symbolic"
assert_not_contains "new install: no stock_smiley-1" "$(cat "$LAUNCHER")" "stock_smiley-1"
assert_contains "new install: icons matched to the theme" "$(cat "$MOCK_CALLS")" "ohmydebn-theme-set-menu-icon"
rm -rf "$SCRATCH_HOME"

# Scenario 2: update from an older release - the old default icon is
# replaced, and nothing else in the file changes.
SCRATCH_HOME=$(mktemp -d)
LAUNCHER="$SCRATCH_HOME/.local/share/applications/ohmydebn-menu.desktop"
write_old_launcher stock_smiley-1
EXPECTED=$(sed 's/^Icon=stock_smiley-1$/Icon=ohmydebn-menu-symbolic/' "$LAUNCHER")
run_menu_sh
assert_eq "update: old default icon replaced, rest unchanged" "$EXPECTED" "$(cat "$LAUNCHER")"
run_menu_sh
assert_eq "update: running again changes nothing" "$EXPECTED" "$(cat "$LAUNCHER")"
rm -rf "$SCRATCH_HOME"

# Scenario 3: the user picked their own icon - it stays.
SCRATCH_HOME=$(mktemp -d)
LAUNCHER="$SCRATCH_HOME/.local/share/applications/ohmydebn-menu.desktop"
write_old_launcher my-favorite-icon
BEFORE=$(cat "$LAUNCHER")
run_menu_sh
assert_eq "custom icon: launcher left alone" "$BEFORE" "$(cat "$LAUNCHER")"
rm -rf "$SCRATCH_HOME"

# Scenario 4: a failing theme hook doesn't stop the install step.
mock_bin ohmydebn-theme-set-menu-icon <<'EOF'
#!/bin/bash
exit 1
EOF
SCRATCH_HOME=$(mktemp -d)
LAUNCHER="$SCRATCH_HOME/.local/share/applications/ohmydebn-menu.desktop"
HOME="$SCRATCH_HOME" bash -c "source '$MOCK_DIR/menu-patched.sh'; echo after" </dev/null >"$MOCK_DIR/out" 2>&1
assert_contains "failing hook: install continues" "$(cat "$MOCK_DIR/out")" "after"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
