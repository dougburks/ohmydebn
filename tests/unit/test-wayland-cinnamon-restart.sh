#!/bin/bash
#
# Unit tests for the two places outside an update that restarted Cinnamon
# with cinnamon --replace: the OhMyDebn menu's System > Relaunch, and
# switching to an Aether theme (to refresh window borders). That's an X11
# window manager's handover; in Cinnamon's Wayland session Cinnamon is the
# display server itself, and can't be replaced without ending the session.
# Relaunch there says to log out and back in. Aether needs no restart at
# all now: each palette's generated theme has a name of its own, so
# Cinnamon reloads it live, as for a theme from the theme picker.
# cinnamon and notify-send are stand-ins that only log, so no real
# Cinnamon is ever touched.

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
# aether <session type> [theme name] [colors file]: ohmydebn-theme-set-cinnamon
# applying that theme (aether by default) with those colors, in a fresh
# HOME unless KEEP_HOME is set
aether() {
  [ -z "${KEEP_HOME:-}" ] && { mock_init; stubs; }
  : >"$MOCK_CALLS"
  H="$MOCK_DIR/home"
  local templates="$MOCK_DIR/templates" wayland=""
  mkdir -p "$templates/Gruvbox-Yellow-Dark/gtk-3.0" "$H/.themes" "$H/.config/ohmydebn/current"
  printf '[Desktop Entry]\nName=Gruvbox-Yellow-Dark\n[X-GNOME-Metatheme]\nGtkTheme=Gruvbox-Yellow-Dark\n' \
    >"$templates/Gruvbox-Yellow-Dark/index.theme"
  echo "* { color: #d8a657; }" >"$templates/Gruvbox-Yellow-Dark/gtk-3.0/gtk.css"
  echo "${2:-aether}" >"$H/.config/ohmydebn/current/theme.name"
  sed "s#/usr/share/ohmydebn-templates#$templates#g; s#/usr/bin/cinnamon#$MOCK_BIN/cinnamon#g" \
    "$REPO_ROOT/bin/ohmydebn-theme-set-cinnamon" >"$MOCK_DIR/hook"
  [ "$1" = wayland ] && wayland="wayland-0"
  HOME="$H" PATH="$(mock_path)" XDG_SESSION_TYPE="$1" WAYLAND_DISPLAY="$wayland" \
    bash "$MOCK_DIR/hook" "${2:-aether}" "${3:-$REPO_ROOT/themes/ohmydebn/colors.toml}" false </dev/null >/dev/null 2>&1
  STATUS=$?
  settle
  CALLS=$(cat "$MOCK_CALLS")
  THEME=$(grep -oP 'gsettings set org.cinnamon.desktop.interface gtk-theme \K\S+' <<<"$CALLS" | tail -1)
}

# Two Aether palettes, as Aether writes them one after the other.
PALETTES=$(mktemp -d)
cp "$REPO_ROOT/themes/ohmydebn/colors.toml" "$PALETTES/first.toml"
sed 's/^accent = .*/accent = "#e06c75"/' "$REPO_ROOT/themes/ohmydebn/colors.toml" >"$PALETTES/second.toml"

for session in x11 wayland; do
  aether "$session" aether "$PALETTES/first.toml"
  FIRST="$THEME"
  assert_eq "Aether, $session: applies" "0" "$STATUS"
  assert_eq "Aether, $session: the theme is named after its palette" "yes" \
    "$([[ "$FIRST" =~ ^ohmydebn-aether-[0-9a-f]{8}$ ]] && echo yes || echo no)"
  assert_contains "Aether, $session: Cinnamon's theme switched to the same name" "$CALLS" "gsettings set org.cinnamon.theme name $FIRST"
  assert_not_contains "Aether, $session: no Cinnamon restart" "$CALLS" "cinnamon --replace"
  assert_not_contains "Aether, $session: no notice" "$CALLS" "notify-send"
  assert_not_contains "Aether, $session: no switch to another GTK theme first" "$CALLS" "Mint-Y"

  KEEP_HOME=1 aether "$session" aether "$PALETTES/second.toml"
  assert_eq "Aether, $session: a second palette is a new theme name, so Cinnamon reloads" "yes" \
    "$([ -n "$THEME" ] && [ "$THEME" != "$FIRST" ] && echo yes || echo no)"
  assert_eq "Aether, $session: the first palette's folder is removed" "no" \
    "$([ -e "$H/.themes/$FIRST" ] && echo yes || echo no)"
  assert_eq "Aether, $session: the second palette's folder is there" "yes" \
    "$([ -f "$H/.themes/$THEME/index.theme" ] && echo yes || echo no)"
  SECOND="$THEME"

  KEEP_HOME=1 aether "$session" aether "$PALETTES/second.toml"
  assert_eq "Aether, $session: the same palette again keeps its name" "$SECOND" "$THEME"
  mock_cleanup
done

# A theme from the theme picker keeps its plain name.
aether wayland nord
assert_eq "another theme: named after the theme, as before" "ohmydebn-nord" "$THEME"
assert_not_contains "another theme: no restart" "$CALLS" "cinnamon --replace"
mock_cleanup
rm -rf "$PALETTES"

test_summary
