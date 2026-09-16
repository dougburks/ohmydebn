#!/bin/bash
#
# Unit tests for install/finalization/default-session.sh - making Cinnamon
# the default login session on an install whose base image shipped another
# desktop (XFCE on Devuan/LCOS). Two layers are covered: pinning the
# x-session-manager alternative to cinnamon-session (what SLiM's no-choice
# login and LightDM's "Default Xsession" both run - on the
# cinnamon-session/startxfce4 priority tie update-alternatives keeps the
# first-installed one, XFCE), and LightDM's user-session default via a
# lightdm.conf.d drop-in plus fixing an explicit override in lightdm.conf.
#
# update-alternatives/ohmydebn-headline are mocked, sudo is mocked to log
# and then run its command, and the script's hardcoded system paths are
# patched to scratch files - so the file edits really happen (and can be
# asserted on) but only ever under $MOCK_DIR.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/finalization/default-session.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/finalization/default-session.sh ==="

SET_CALL="sudo update-alternatives --set x-session-manager"
EXPECTED_DROPIN="[Seat:*]
user-session=cinnamon"

# setup <default-display-manager content|ABSENT> <current alternative Value|CINNAMON> <cinnamon-session present: yes|no> <lightdm dir: yes|no> [lightdm.conf content]
setup() {
  local dm="$1" current="$2" have_cinnamon="$3" have_lightdm="$4" conf="${5:-}"
  mock_init
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
exec "$@"
EOF2
  mock_bin update-alternatives <<'EOF2'
#!/bin/bash
mock_log "update-alternatives $*"
if [[ "$1" == "--query" ]]; then
  echo "Name: x-session-manager"
  echo "Value: $MOCK_CURRENT_SESSION_MANAGER"
fi
exit 0
EOF2
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF2
  [[ "$dm" != "ABSENT" ]] && echo "$dm" >"$MOCK_DIR/default-display-manager"
  if [[ "$have_cinnamon" == "yes" ]]; then
    printf '#!/bin/bash\n' >"$MOCK_DIR/cinnamon-session"
    chmod +x "$MOCK_DIR/cinnamon-session"
  fi
  if [[ "$have_lightdm" == "yes" ]]; then
    mkdir -p "$MOCK_DIR/lightdm"
    [[ -n "$conf" ]] && printf '%s\n' "$conf" >"$MOCK_DIR/lightdm/lightdm.conf"
  fi
  [[ "$current" == "CINNAMON" ]] && current="$MOCK_DIR/cinnamon-session"
  export MOCK_CURRENT_SESSION_MANAGER="$current"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#DEFAULT_DM_FILE=/etc/X11/default-display-manager#DEFAULT_DM_FILE=$MOCK_DIR/default-display-manager#; s#CINNAMON_SESSION=/usr/bin/cinnamon-session#CINNAMON_SESSION=$MOCK_DIR/cinnamon-session#; s#LIGHTDM_DIR=/etc/lightdm#LIGHTDM_DIR=$MOCK_DIR/lightdm#" \
    "$SCRIPT" >"$MOCK_DIR/patched.sh"
}

run_script() {
  PATH="$(mock_path)" bash -e "$MOCK_DIR/patched.sh" >"$MOCK_DIR/output" 2>&1
  echo $?
}

DROPIN="lightdm/lightdm.conf.d/50-ohmydebn-session.conf"

# Scenario 1: SLiM, XFCE default, no LightDM -> alternative pinned, F1 hint, no LightDM files
setup "/usr/bin/slim" "/usr/bin/startxfce4" yes no
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "SLiM+XFCE: exits 0" "0" "$EXIT_CODE"
assert_contains "SLiM+XFCE: pins x-session-manager to cinnamon-session" "$CALLS" "$SET_CALL $MOCK_DIR/cinnamon-session"
assert_contains "SLiM+XFCE: headline" "$CALLS" "ohmydebn-headline Setting Cinnamon as the default login session"
assert_contains "SLiM+XFCE: F1 hint shown" "$(cat "$MOCK_DIR/output")" "press F1"
assert_eq "SLiM+XFCE: no LightDM drop-in created" "" "$(ls "$MOCK_DIR/lightdm" 2>/dev/null)"
mock_cleanup

# Scenario 2: LightDM, XFCE default, lightdm.conf with user-session commented out (Debian default)
setup "/usr/sbin/lightdm" "/usr/bin/startxfce4" yes yes "[Seat:*]
#user-session=default
greeter-hide-users=true"
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "LightDM+XFCE: exits 0" "0" "$EXIT_CODE"
assert_contains "LightDM+XFCE: pins x-session-manager too (Default Xsession runs it)" "$CALLS" "$SET_CALL $MOCK_DIR/cinnamon-session"
assert_not_contains "LightDM+XFCE: no F1 hint (LightDM has a menu)" "$(cat "$MOCK_DIR/output")" "press F1"
assert_eq "LightDM+XFCE: drop-in written with the right content" "$EXPECTED_DROPIN" "$(cat "$MOCK_DIR/$DROPIN" 2>/dev/null)"
assert_contains "LightDM+XFCE: drop-in written via sudo" "$CALLS" "sudo tee $MOCK_DIR/$DROPIN"
assert_eq "LightDM+XFCE: commented user-session left alone (no backup made)" "no" \
  "$([[ -f "$MOCK_DIR/lightdm/lightdm.conf.BEFORE.OHMYDEBN" ]] && echo yes || echo no)"
mock_cleanup

# Scenario 3: LightDM with an explicit user-session=xfce in lightdm.conf (would override the drop-in)
setup "/usr/sbin/lightdm" "/usr/bin/startxfce4" yes yes "[Seat:*]
user-session=xfce
greeter-session=lightdm-gtk-greeter"
EXIT_CODE=$(run_script)
assert_eq "LightDM+explicit xfce: exits 0" "0" "$EXIT_CODE"
assert_eq "LightDM+explicit xfce: user-session switched to cinnamon" "user-session=cinnamon" \
  "$(grep '^user-session=' "$MOCK_DIR/lightdm/lightdm.conf")"
assert_eq "LightDM+explicit xfce: other lines untouched" "greeter-session=lightdm-gtk-greeter" \
  "$(grep '^greeter-session=' "$MOCK_DIR/lightdm/lightdm.conf")"
assert_eq "LightDM+explicit xfce: backup of original kept" "user-session=xfce" \
  "$(grep '^user-session=' "$MOCK_DIR/lightdm/lightdm.conf.BEFORE.OHMYDEBN" 2>/dev/null)"
mock_cleanup

# Scenario 4: re-run with everything already in place (update path) -> no sudo at all
setup "/usr/sbin/lightdm" CINNAMON yes yes "[Seat:*]
user-session=cinnamon"
mkdir -p "$MOCK_DIR/lightdm/lightdm.conf.d"
printf '%s\n' "$EXPECTED_DROPIN" >"$MOCK_DIR/$DROPIN"
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "already configured: exits 0" "0" "$EXIT_CODE"
assert_contains "already configured: still queries the alternative" "$CALLS" "update-alternatives --query x-session-manager"
assert_not_contains "already configured: no sudo calls" "$CALLS" "sudo "
assert_not_contains "already configured: no headline" "$CALLS" "ohmydebn-headline"
assert_eq "already configured: lightdm.conf not backed up" "no" \
  "$([[ -f "$MOCK_DIR/lightdm/lightdm.conf.BEFORE.OHMYDEBN" ]] && echo yes || echo no)"
mock_cleanup

# Scenario 5: LightDM installed but no lightdm.conf at all -> drop-in still written, no sed attempted
setup "/usr/sbin/lightdm" CINNAMON yes yes
EXIT_CODE=$(run_script)
assert_eq "LightDM, no lightdm.conf: exits 0" "0" "$EXIT_CODE"
assert_eq "LightDM, no lightdm.conf: drop-in written" "$EXPECTED_DROPIN" "$(cat "$MOCK_DIR/$DROPIN" 2>/dev/null)"
mock_cleanup

# Scenario 6: no display manager file, no LightDM dir -> only the alternative is pinned
setup ABSENT "/usr/bin/startxfce4" yes no
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "no DM: exits 0" "0" "$EXIT_CODE"
assert_contains "no DM: alternative still pinned" "$CALLS" "$SET_CALL"
assert_eq "no DM: nothing else touched" "" "$(ls "$MOCK_DIR/lightdm" 2>/dev/null)"
mock_cleanup

# Scenario 7: cinnamon-session missing -> do nothing at all
setup "/usr/bin/slim" "/usr/bin/startxfce4" no yes
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "no cinnamon-session: exits 0" "0" "$EXIT_CODE"
assert_eq "no cinnamon-session: nothing called" "" "$CALLS"
assert_eq "no cinnamon-session: no drop-in" "no" "$([[ -f "$MOCK_DIR/$DROPIN" ]] && echo yes || echo no)"
mock_cleanup

test_summary
