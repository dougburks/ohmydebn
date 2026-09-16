#!/bin/bash
#
# Unit tests for install/finalization/slim.sh - pinning the x-session-manager
# alternative to cinnamon-session when SLiM is the login manager. SLiM
# (Devuan's default) has no session menu and no memory, and on a
# cinnamon-session/startxfce4 priority tie update-alternatives keeps the
# first-installed one (XFCE), so without this step a plain login after
# installing OhMyDebn on Devuan silently lands back in XFCE.
#
# sudo/update-alternatives/ohmydebn-headline are mocked, and the script's
# hardcoded /etc/X11/default-display-manager and /usr/bin/cinnamon-session
# paths are patched to scratch files, so nothing here touches the real
# system's alternatives.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/finalization/slim.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/finalization/slim.sh (SLiM default session) ==="

SET_CALL="sudo update-alternatives --set x-session-manager"

# setup <default-display-manager content or "ABSENT"> <current alternative Value> <cinnamon-session present: yes|no>
setup() {
  local dm="$1" current="$2" have_cinnamon="$3"
  mock_init
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF2
  mock_bin update-alternatives <<'EOF2'
#!/bin/bash
mock_log "update-alternatives $*"
if [[ "$1" == "--query" ]]; then
  echo "Name: x-session-manager"
  echo "Link: /usr/bin/x-session-manager"
  echo "Status: auto"
  echo "Best: $MOCK_CURRENT_SESSION_MANAGER"
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
  # Patch the fixed paths to scratch equivalents; the --set assertion below
  # checks the patched cinnamon-session path, which is what the -x test and
  # the --query comparison both see in this run.
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#DEFAULT_DM_FILE=/etc/X11/default-display-manager#DEFAULT_DM_FILE=$MOCK_DIR/default-display-manager#; s#CINNAMON_SESSION=/usr/bin/cinnamon-session#CINNAMON_SESSION=$MOCK_DIR/cinnamon-session#" \
    "$SCRIPT" >"$MOCK_DIR/slim-patched.sh"
  export MOCK_CURRENT_SESSION_MANAGER="$current"
}

run_script() {
  PATH="$(mock_path)" bash -e "$MOCK_DIR/slim-patched.sh" >"$MOCK_DIR/output" 2>&1
  echo $?
}

# Scenario 1: SLiM, alternative currently XFCE -> pinned to cinnamon-session
setup "/usr/bin/slim" "/usr/bin/startxfce4" yes
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "SLiM+XFCE default: exits 0" "0" "$EXIT_CODE"
assert_contains "SLiM+XFCE default: pins x-session-manager to cinnamon-session" "$CALLS" "$SET_CALL $MOCK_DIR/cinnamon-session"
assert_contains "SLiM+XFCE default: headline explains the change" "$CALLS" "ohmydebn-headline Setting Cinnamon as the default login session for SLiM"
assert_contains "SLiM+XFCE default: tells the user about F1" "$(cat "$MOCK_DIR/output")" "press F1"
mock_cleanup

# Scenario 2: SLiM, already cinnamon-session -> no change (idempotent on re-runs/updates)
setup "/usr/bin/slim" "PLACEHOLDER" yes
export MOCK_CURRENT_SESSION_MANAGER="$MOCK_DIR/cinnamon-session"
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "SLiM+already Cinnamon: exits 0" "0" "$EXIT_CODE"
assert_contains "SLiM+already Cinnamon: queried the alternative" "$CALLS" "update-alternatives --query x-session-manager"
assert_not_contains "SLiM+already Cinnamon: no --set call" "$CALLS" "$SET_CALL"
assert_not_contains "SLiM+already Cinnamon: no headline" "$CALLS" "ohmydebn-headline"
mock_cleanup

# Scenario 3: LightDM -> untouched (it has its own session picker and memory)
setup "/usr/sbin/lightdm" "/usr/bin/startxfce4" yes
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "LightDM: exits 0" "0" "$EXIT_CODE"
assert_eq "LightDM: nothing called at all" "" "$CALLS"
mock_cleanup

# Scenario 4: no default-display-manager file (no display manager installed) -> untouched
setup ABSENT "/usr/bin/startxfce4" yes
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "no DM file: exits 0" "0" "$EXIT_CODE"
assert_eq "no DM file: nothing called" "" "$CALLS"
mock_cleanup

# Scenario 5: SLiM but cinnamon-session missing -> don't pin a nonexistent target
setup "/usr/bin/slim" "/usr/bin/startxfce4" no
EXIT_CODE=$(run_script)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "SLiM, no cinnamon-session: exits 0" "0" "$EXIT_CODE"
assert_not_contains "SLiM, no cinnamon-session: no --set call" "$CALLS" "$SET_CALL"
mock_cleanup

test_summary
