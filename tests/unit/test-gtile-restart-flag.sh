#!/bin/bash
#
# Unit tests for install/finalization/gtile-restart-flag.sh. Cinnamon loads an
# extension's JS into the already-running process - upgrading
# ohmydebn-gtile on disk alone doesn't reach a session that's already
# running until Cinnamon reloads it. This script doesn't restart Cinnamon
# directly - two independent backgrounded `cinnamon --replace &` calls in
# the same run would race each other (install/keybinding/keybinding.sh used
# to schedule one too, before it learned to reload keybindings live).
# Instead this sets OHMYDEBN_CINNAMON_RESTART_NEEDED, a plain shell
# variable shared across every finalization script sourced into the same
# process (see finalization/all.sh) - finalization/finale.sh does the one
# actual restart at the end if anything asked for it (see
# test-finale-restart.sh).
#
# This lives in install/finalization/ (sourced right after updates.sh,
# which is what actually runs `apt upgrade`) rather than
# install/config/cinnamon.sh - config/all.sh runs *before*
# finalization/all.sh, so checking dpkg-query from cinnamon.sh would see
# the pre-upgrade version and flag a restart before ohmydebn-gtile had
# actually been upgraded that run (confirmed live).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/finalization/gtile-restart-flag.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/finalization/gtile-restart-flag.sh ==="

setup_mocks() {
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF
  mock_bin dpkg-query <<'EOF'
#!/bin/bash
mock_log "dpkg-query $*"
if [[ -n "${DPKG_GTILE_VERSION:-}" ]]; then
  echo -n "$DPKG_GTILE_VERSION"
  exit 0
fi
exit 1
EOF
  mock_bin gsettings <<'EOF'
#!/bin/bash
mock_log "gsettings $*"
if [[ "$1" == "get" && "$2" == "org.cinnamon" && "$3" == "enabled-extensions" ]]; then
  echo "${MOCK_ENABLED_EXTENSIONS:-['gTile@OhMyDebn']}"
fi
exit 0
EOF
  # pgrep -x cinnamon is how the real script checks for a live session to
  # restart - mocked so the test controls it instead of depending on
  # whatever's actually running on the machine the tests execute on.
  mock_bin pgrep <<'EOF'
#!/bin/bash
mock_log "pgrep $*"
if [[ "${MOCK_CINNAMON_RUNNING:-true}" == "true" ]]; then
  echo "12345"
  exit 0
fi
exit 1
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/gtile-restart-patched.sh"
}

# Sources (doesn't exec) the patched script, matching how the real
# pipeline invokes it (finalization/all.sh sources every finalization
# script into the same shell) - required to observe
# OHMYDEBN_CINNAMON_RESTART_NEEDED, which only propagates back to the
# caller via `source`, not a subprocess. Sets RESTART_FLAG and RELOAD_FLAG
# to "1" or "", read from marker lines the wrapper prints after it.
# OHMYDEBN_CINNAMON_RESTART_NEEDED= clears whatever this var already is in
# the ambient environment before the child bash starts - on a real OhMyDebn
# desktop session it's commonly already exported to 1, and since the script
# under test only ever sets it (never unsets it), an inherited 1 would leak
# straight through and look like a false-positive restart flag on every
# scenario that expects none.
run_script() {
  local output
  # An X11 session unless MOCK_SESSION_TYPE says otherwise, whatever
  # session the tests themselves run in.
  output=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" OHMYDEBN_CINNAMON_RESTART_NEEDED='' \
    OHMYDEBN_GTILE_RELOAD_NEEDED='' WAYLAND_DISPLAY='' XDG_SESSION_TYPE="${MOCK_SESSION_TYPE:-x11}" \
    MOCK_CINNAMON_RUNNING="${MOCK_CINNAMON_RUNNING:-true}" bash -c "
    source '$MOCK_DIR/gtile-restart-patched.sh'
    echo \"GTILE_TEST_FLAG_MARKER:\${OHMYDEBN_CINNAMON_RESTART_NEEDED:-}\"
    echo \"GTILE_TEST_RELOAD_MARKER:\${OHMYDEBN_GTILE_RELOAD_NEEDED:-}\"
  " 2>/dev/null)
  RESTART_FLAG=$(echo "$output" | sed -n 's/^GTILE_TEST_FLAG_MARKER://p')
  RELOAD_FLAG=$(echo "$output" | sed -n 's/^GTILE_TEST_RELOAD_MARKER://p')
}

# Scenario 1: first run ever, gTile installed and enabled -> flags a
# restart and records the version it flagged for.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
DPKG_GTILE_VERSION="2.8.1-20260831" run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "first run, version installed+enabled: restart flagged" "1" "$RESTART_FLAG"
assert_contains "first run: restart headline shown" "$CALLS" "Cinnamon will restart at the end for gTile"
assert_eq "first run: restart-version state file written" "2.8.1-20260831" \
  "$(cat "$SCRATCH_HOME/.local/state/ohmydebn-config/gtile-cinnamon-restart-version" 2>/dev/null)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: second run, same version already recorded -> no flag.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
echo -n "2.8.1-20260831" >"$SCRATCH_HOME/.local/state/ohmydebn-config/gtile-cinnamon-restart-version"
DPKG_GTILE_VERSION="2.8.1-20260831" run_script
assert_eq "same version already flagged for: no restart flag" "" "$RESTART_FLAG"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: version bumped since the last recorded restart (the actual
# post-upgrade case this script exists for) -> flags again and updates
# the recorded version.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
echo -n "2.8.1-20260831" >"$SCRATCH_HOME/.local/state/ohmydebn-config/gtile-cinnamon-restart-version"
DPKG_GTILE_VERSION="2.9.0-20260901" run_script
assert_eq "version bumped: restart flagged again" "1" "$RESTART_FLAG"
assert_eq "version bumped: restart-version state file updated" "2.9.0-20260901" \
  "$(cat "$SCRATCH_HOME/.local/state/ohmydebn-config/gtile-cinnamon-restart-version" 2>/dev/null)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 4: gTile installed but the user has disabled it -> no flag,
# and no restart-version state file written either (nothing to remember).
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
MOCK_ENABLED_EXTENSIONS="[]" DPKG_GTILE_VERSION="2.8.1-20260831" run_script
assert_eq "gTile disabled: no restart flag" "" "$RESTART_FLAG"
assert_eq "gTile disabled: no restart-version state file written" "no" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/gtile-cinnamon-restart-version" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 5: ohmydebn-gtile not installed at all -> no flag. (The
# ohmydebn package requires it now, so this is a safety net.)
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_script
assert_eq "gTile not installed: no restart flag" "" "$RESTART_FLAG"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 6: version bumped, but no Cinnamon session is running (the
# install or update ran from XFCE on an LCOS/Devuan base, say) -> no
# restart flag and no "Cinnamon will restart" headline, since finale.sh
# checks the same thing and wouldn't restart anything; the version is
# still recorded, because the extension loads fresh at the next Cinnamon
# login and no restart is owed for it later.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
MOCK_CINNAMON_RUNNING=false DPKG_GTILE_VERSION="2.9.0-20260901" run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "no Cinnamon session: no restart flag" "" "$RESTART_FLAG"
assert_not_contains "no Cinnamon session: no 'will restart' headline" "$CALLS" "Cinnamon will restart"
assert_eq "no Cinnamon session: restart-version state file still written" "2.9.0-20260901" \
  "$(cat "$SCRATCH_HOME/.local/state/ohmydebn-config/gtile-cinnamon-restart-version" 2>/dev/null)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario: a new gTile in Cinnamon's Wayland session. Cinnamon is the
# display server there, and cinnamon --replace can't restart it; Cinnamon
# reloads just the extension instead, which finale.sh asks for.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
echo -n "3.0.1-20261102" >"$SCRATCH_HOME/.local/state/ohmydebn-config/gtile-cinnamon-restart-version"
MOCK_SESSION_TYPE=wayland DPKG_GTILE_VERSION="3.0.1-20261112" run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "Wayland, version bumped: no Cinnamon restart flagged" "" "$RESTART_FLAG"
assert_eq "Wayland, version bumped: a gTile reload flagged" "1" "$RELOAD_FLAG"
assert_contains "Wayland: says gTile will reload" "$CALLS" "gTile will reload at the end"
assert_not_contains "Wayland: doesn't say Cinnamon will restart" "$CALLS" "Cinnamon will restart"
assert_eq "Wayland: the version is recorded as handled" "3.0.1-20261112" \
  "$(cat "$SCRATCH_HOME/.local/state/ohmydebn-config/gtile-cinnamon-restart-version" 2>/dev/null)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# The same bump on X11 still restarts Cinnamon, as before.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
DPKG_GTILE_VERSION="3.0.1-20261112" run_script
assert_eq "X11, version bumped: Cinnamon restart flagged" "1" "$RESTART_FLAG"
assert_eq "X11, version bumped: no reload flag" "" "$RELOAD_FLAG"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
