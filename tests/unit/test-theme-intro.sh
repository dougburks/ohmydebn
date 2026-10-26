#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-intro, which decides whether a
# background's intro plays and which, and bin/ohmydebn-theme-intro-toggle,
# which turns intros off and on. A background's own clip is
# backgrounds/intros/<background name>.webm (or .mp4), looked for only in a
# stock theme the user hasn't replaced with their own and in the user's own
# backgrounds folder - never in a theme installed from a git repo, whose
# video would otherwise be fed to a decoder. Every other background gets
# the light intro, drawn from the image itself (--light). Intros don't play
# with desktop effects or animations off, on a Raspberry Pi, or when turned
# off. They do play in a virtual machine.
#
# HOME and the stock themes folder are scratch directories; the player,
# gsettings and systemd-detect-virt are stand-ins. The player logs the clip
# it was given and prints "ready", as the real one does once it covers the
# screen.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-intro / ohmydebn-theme-intro-toggle ==="

setup() {
  mock_init
  H="$MOCK_DIR/home"
  STOCK="$MOCK_DIR/stock"
  CURRENT="$H/.config/ohmydebn/current"
  mkdir -p "$CURRENT/theme/backgrounds" "$STOCK/retro-82/backgrounds/intros"
  echo retro-82 >"$CURRENT/theme.name"
  : >"$STOCK/retro-82/backgrounds/1-in-the-groove.jpg"
  : >"$STOCK/retro-82/backgrounds/intros/1-in-the-groove.webm"
  : >"$STOCK/retro-82/backgrounds/2-dusk-guardian.jpg"
  # ohmydebn-theme-set's copy of the theme, without its intros.
  cp "$STOCK/retro-82/backgrounds/"*.jpg "$CURRENT/theme/backgrounds/"
  ln -s "$CURRENT/theme/backgrounds/1-in-the-groove.jpg" "$CURRENT/background"

  mock_bin ohmydebn-theme-intro-play <<'EOF'
#!/bin/bash
mock_log "play $*"
[[ -n "${MOCK_PLAYER_SILENT:-}" ]] && { sleep 2; exit 1; }
echo ready
EOF
  mock_bin gsettings <<'EOF'
#!/bin/bash
case "$2 $3" in
"org.cinnamon desktop-effects-workspace") echo "${MOCK_EFFECTS:-true}" ;;
"org.cinnamon.desktop.interface enable-animations") echo "${MOCK_ANIMATIONS:-true}" ;;
esac
EOF
  mock_bin notify-send <<'EOF'
#!/bin/bash
exit 0
EOF
  mock_bin systemd-detect-virt <<'EOF'
#!/bin/bash
[[ -n "${MOCK_VM:-}" ]]
EOF
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#^STOCK_THEMES=.*#STOCK_THEMES=$STOCK#" \
    -e "s#^WAIT_SECONDS=.*#WAIT_SECONDS=1#" \
    "$REPO_ROOT/bin/ohmydebn-theme-intro" >"$MOCK_DIR/intro"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-theme-intro-toggle" >"$MOCK_DIR/toggle"
}
# --wait returns once the stand-in player has logged and said "ready", so
# what it was asked to play is in the log by then.
intro() {
  HOME="$H" DISPLAY="${MOCK_DISPLAY-:99}" PATH="$(mock_path)" \
    OHMYDEBN_TEST_DEVICE_TREE_MODEL="${MOCK_MODEL:-$MOCK_DIR/no-model}" \
    bash "$MOCK_DIR/intro" "$@" </dev/null
}
played() { cat "$MOCK_CALLS"; }
STOCK_CLIP() { echo "play $STOCK/retro-82/backgrounds/intros/1-in-the-groove.webm"; }
LIGHT() { echo "play --light $1"; }

# --- a stock theme's background: its intro plays, from the theme package ---
setup
intro --wait "$CURRENT/theme/backgrounds/1-in-the-groove.jpg"
assert_eq "stock theme: the background's intro plays" "$(STOCK_CLIP)" "$(played)"
mock_cleanup

setup
intro --wait
assert_eq "no background named: the current background's intro" "$(STOCK_CLIP)" "$(played)"
mock_cleanup

setup
rm "$STOCK/retro-82/backgrounds/intros/1-in-the-groove.webm"
: >"$STOCK/retro-82/backgrounds/intros/1-in-the-groove.mp4"
intro --wait
assert_eq "an .mp4 intro plays too" "play $STOCK/retro-82/backgrounds/intros/1-in-the-groove.mp4" "$(played)"
mock_cleanup

setup
intro --wait "$CURRENT/theme/backgrounds/2-dusk-guardian.jpg"
assert_eq "a background without a clip: the light intro, from the image" \
  "$(LIGHT "$CURRENT/theme/backgrounds/2-dusk-guardian.jpg")" "$(played)"
: >"$MOCK_CALLS"
intro --wait "$CURRENT/theme/backgrounds/gone.jpg"
assert_eq "a background that isn't there: nothing plays" "" "$(played)"
mock_cleanup

# --- a theme of the user's own by a stock theme's name is the one in use ---
setup
mkdir -p "$H/.config/ohmydebn/themes/retro-82"
intro --wait
assert_eq "the user's own theme replaces the stock one: the light intro, not the stock clip" \
  "$(LIGHT "$CURRENT/theme/backgrounds/1-in-the-groove.jpg")" "$(played)"
mock_cleanup

# --- a theme installed from a git repo: its intros never play ---
setup
echo stranger >"$CURRENT/theme.name"
mkdir -p "$H/.config/ohmydebn/themes/stranger/.git" "$H/.config/ohmydebn/themes/stranger/backgrounds/intros"
: >"$H/.config/ohmydebn/themes/stranger/backgrounds/1-in-the-groove.jpg"
: >"$H/.config/ohmydebn/themes/stranger/backgrounds/intros/1-in-the-groove.webm"
mkdir -p "$CURRENT/theme/backgrounds/intros"
: >"$CURRENT/theme/backgrounds/intros/1-in-the-groove.webm"
intro --wait
assert_eq "a theme from a git repo: the light intro, never its clip" \
  "$(LIGHT "$CURRENT/theme/backgrounds/1-in-the-groove.jpg")" "$(played)"
mock_cleanup

# --- the user's own backgrounds folder: an intro beside their image plays ---
setup
USER_BG="$H/.config/ohmydebn/backgrounds/retro-82"
mkdir -p "$USER_BG/intros"
: >"$USER_BG/beach.png"
: >"$USER_BG/intros/beach.mp4"
intro --wait "$USER_BG/beach.png"
assert_eq "the user's own background: its intro plays" "play $USER_BG/intros/beach.mp4" "$(played)"
: >"$MOCK_CALLS"
: >"$USER_BG/other.png"
intro --wait "$USER_BG/other.png"
assert_eq "the user's own background without one: the light intro" "$(LIGHT "$USER_BG/other.png")" "$(played)"
mock_cleanup

# --- when intros don't play at all ---
setup
HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/toggle" off </dev/null >/dev/null 2>&1
intro --wait
assert_eq "turned off: nothing plays" "" "$(played)"
mock_cleanup

setup
MOCK_EFFECTS=false intro --wait
assert_eq "desktop effects off: nothing plays" "" "$(played)"
MOCK_ANIMATIONS=false intro --wait
assert_eq "animations off: nothing plays" "" "$(played)"
MOCK_VM=1 intro --wait
assert_eq "in a VM: the intro plays" "$(STOCK_CLIP)" "$(played)"
: >"$MOCK_CALLS"
MOCK_DISPLAY="" intro --wait
assert_eq "no display: nothing plays" "" "$(played)"
intro --wait
assert_eq "...and with none of those, it does" "$(STOCK_CLIP)" "$(played)"
mock_cleanup

setup
printf 'Raspberry Pi 5 Model B Rev 1.0\0' >"$MOCK_DIR/model"
MOCK_MODEL="$MOCK_DIR/model" intro --wait
assert_eq "on a Raspberry Pi: nothing plays" "" "$(played)"
printf 'QEMU Virt Machine\0' >"$MOCK_DIR/model"
MOCK_MODEL="$MOCK_DIR/model" intro --wait
assert_eq "another device-tree machine: the intro plays" "$(STOCK_CLIP)" "$(played)"
mock_cleanup

# --- it never holds up or fails a theme switch ---
setup
START=$SECONDS
MOCK_PLAYER_SILENT=1 intro --wait
STATUS=$?
assert_eq "a player that never covers the screen: still succeeds" "0" "$STATUS"
assert_eq "...after giving it the wait limit, not until it exits" "yes" "$([ $((SECONDS - START)) -le 1 ] && echo yes || echo no)"
mock_cleanup

setup
intro
for _ in $(seq 20); do [[ -s "$MOCK_CALLS" ]] && break; sleep 0.1; done
assert_eq "without --wait: the intro still plays, on its own" "$(STOCK_CLIP)" "$(played)"
mock_cleanup

# --- the toggle ---
setup
toggle() { HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/toggle" "$@" </dev/null 2>&1; }
OFF="$H/.config/ohmydebn/theme-intros-off"
assert_eq "toggle with no setting yet: turns them off" "Theme intros are off" "$(toggle)"
assert_eq "...with a marker" "yes" "$([ -e "$OFF" ] && echo yes || echo no)"
assert_eq "toggle again: back on" "Theme intros are on" "$(toggle)"
assert_eq "...marker gone" "no" "$([ -e "$OFF" ] && echo yes || echo no)"
toggle off >/dev/null
toggle off >/dev/null
assert_eq "off twice stays off" "yes" "$([ -e "$OFF" ] && echo yes || echo no)"
toggle on >/dev/null
assert_eq "on" "no" "$([ -e "$OFF" ] && echo yes || echo no)"
toggle sideways >/dev/null
assert_eq "an unknown setting is refused" "1" "$?"
mock_cleanup

test_summary
