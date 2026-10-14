#!/bin/bash
#
# Unit tests for install/config/menu.sh: writes the OhMyDebn Menu launcher
# with the ohmydebn-menu-symbolic icon, and moves launchers written before
# 4.12.0 off stock_smiley-1 (an icon LMDE 7 doesn't install) without
# touching an icon the user chose.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/menu.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/menu.sh ==="

run_menu_sh() {
  HOME="$SCRATCH_HOME" bash "$SCRIPT" </dev/null >/dev/null 2>&1
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

# The icon the launcher names must be the one the package installs.
assert_eq "icon file ships in config/icons" "yes" \
  "$([ -f "$REPO_ROOT/config/icons/ohmydebn-menu-symbolic.svg" ] && echo yes || echo no)"
assert_contains "package build installs the icon into hicolor" \
  "$(cat "$REPO_ROOT/../ohmydebn-package-build/build-package-ohmydebn.sh" 2>/dev/null)" \
  "config/icons/ohmydebn-menu-symbolic.svg\"=/usr/share/icons/hicolor/scalable/apps/ohmydebn-menu-symbolic.svg"

# Scenario 1: new install - the launcher is written with the new icon.
SCRATCH_HOME=$(mktemp -d)
LAUNCHER="$SCRATCH_HOME/.local/share/applications/ohmydebn-menu.desktop"
run_menu_sh
assert_contains "new install: launcher uses the symbolic icon" "$(cat "$LAUNCHER")" "Icon=ohmydebn-menu-symbolic"
assert_not_contains "new install: no stock_smiley-1" "$(cat "$LAUNCHER")" "stock_smiley-1"
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

test_summary
