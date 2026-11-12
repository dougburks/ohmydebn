#!/bin/bash
#
# Unit tests for the two places outside an update that restarted Cinnamon
# with cinnamon --replace: the OhMyDebn menu's System > Relaunch, and
# switching to an Aether theme (to refresh window borders). That's an X11
# window manager's handover; in Cinnamon's Wayland session Cinnamon is the
# display server itself, and can't be replaced without ending the session.
# There each now says what to do instead. cinnamon and notify-send are
# stand-ins that only log, so no real Cinnamon is ever touched.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== cinnamon --replace only outside Wayland: Relaunch, Aether themes ==="

stubs() {
  printf '#!/bin/bash\nmock_log "cinnamon $*"\n' | mock_bin cinnamon
  printf '#!/bin/bash\nmock_log "notify-send $*"\n' | mock_bin notify-send
  printf '#!/bin/bash\nmock_log "gsettings $*"\n' | mock_bin gsettings
}

# The backgrounded restart may log a moment after the script returns.
settle() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -q "cinnamon --replace" "$MOCK_CALLS" 2>/dev/null && return
    sleep 0.1
  done
}

# --- System > Relaunch ---
# relaunch <session type>: show_system_menu with the picker answering
# Relaunch, in a Wayland (wayland) or X11 (x11) session
relaunch() {
  mock_init
  stubs
  sed "s#/usr/bin/cinnamon#$MOCK_BIN/cinnamon#g; /^show_main_menu\$/d" "$REPO_ROOT/bin/ohmydebn-menu" >"$MOCK_DIR/menu"
  local wayland=""
  [ "$1" = wayland ] && wayland="wayland-0"
  HOME="$MOCK_DIR" PATH="$(mock_path)" XDG_SESSION_TYPE="$1" WAYLAND_DISPLAY="$wayland" bash -c '
    source "$1" 2>/dev/null
    menu() { MENU_RESULT="  Relaunch"; }
    show_system_menu
  ' _ "$MOCK_DIR/menu" </dev/null >/dev/null 2>&1
  settle
  CALLS=$(cat "$MOCK_CALLS")
}

relaunch x11
assert_contains "Relaunch, X11: Cinnamon is relaunched" "$CALLS" "cinnamon --replace"
assert_not_contains "Relaunch, X11: no notice" "$CALLS" "notify-send"
mock_cleanup

relaunch wayland
assert_not_contains "Relaunch, Wayland: Cinnamon isn't replaced" "$CALLS" "cinnamon --replace"
assert_contains "Relaunch, Wayland: says to log out and back in" "$CALLS" "Log out and back in instead"
mock_cleanup

# --- an Aether theme ---
# aether <session type> [theme name]: ohmydebn-theme-set-cinnamon applying
# that theme (aether by default)
aether() {
  mock_init
  stubs
  local h="$MOCK_DIR/home" templates="$MOCK_DIR/templates" wayland=""
  mkdir -p "$templates/Gruvbox-Yellow-Dark/gtk-3.0" "$h/.themes" "$h/.config/ohmydebn/current"
  printf '[Desktop Entry]\nName=Gruvbox-Yellow-Dark\n[X-GNOME-Metatheme]\nGtkTheme=Gruvbox-Yellow-Dark\n' \
    >"$templates/Gruvbox-Yellow-Dark/index.theme"
  echo "* { color: #d8a657; }" >"$templates/Gruvbox-Yellow-Dark/gtk-3.0/gtk.css"
  echo "${2:-aether}" >"$h/.config/ohmydebn/current/theme.name"
  sed "s#/usr/share/ohmydebn-templates#$templates#g; s#/usr/bin/cinnamon#$MOCK_BIN/cinnamon#g" \
    "$REPO_ROOT/bin/ohmydebn-theme-set-cinnamon" >"$MOCK_DIR/hook"
  [ "$1" = wayland ] && wayland="wayland-0"
  HOME="$h" PATH="$(mock_path)" XDG_SESSION_TYPE="$1" WAYLAND_DISPLAY="$wayland" \
    bash "$MOCK_DIR/hook" "${2:-aether}" "$REPO_ROOT/themes/ohmydebn/colors.toml" false </dev/null >/dev/null 2>&1
  STATUS=$?
  settle
  CALLS=$(cat "$MOCK_CALLS")
}

aether x11
assert_eq "Aether, X11: applies" "0" "$STATUS"
assert_contains "Aether, X11: Cinnamon restarts for the window borders" "$CALLS" "cinnamon --replace"
mock_cleanup

aether wayland
assert_eq "Aether, Wayland: applies" "0" "$STATUS"
assert_contains "Aether, Wayland: the theme is still switched" "$CALLS" "gsettings set org.cinnamon.theme name ohmydebn-aether"
assert_not_contains "Aether, Wayland: Cinnamon isn't replaced" "$CALLS" "cinnamon --replace"
assert_contains "Aether, Wayland: says the borders change at the next login" "$CALLS" "the next time you log in"
mock_cleanup

aether wayland nord
assert_not_contains "another theme, Wayland: no notice" "$CALLS" "notify-send"
assert_not_contains "another theme, Wayland: no restart" "$CALLS" "cinnamon --replace"
mock_cleanup

test_summary
