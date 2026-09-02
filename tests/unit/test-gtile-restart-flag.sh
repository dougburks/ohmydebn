#!/bin/bash
#
# Unit tests for install/finalization/gtile-restart-flag.sh. Cinnamon loads an
# extension's JS into the already-running process - upgrading
# ohmydebn-gtile on disk alone doesn't reach a session that's already
# running until Cinnamon reloads it. This script doesn't restart Cinnamon
# directly - install/keybinding/keybinding.sh can also decide a restart is
# needed, for its own unrelated reason, and two independent backgrounded
# `cinnamon --replace &` calls in the same run would race each other.
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
#
# Also covers the ohmydebn-gtile minimum-version warning, which used to
# live in install/config/cinnamon.sh for the same reason (same stale-
# version problem, plus it had zero test coverage anywhere before this).

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
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/gtile-restart-patched.sh"
}

# Sources (doesn't exec) the patched script, matching how the real
# pipeline invokes it (finalization/all.sh sources every finalization
# script into the same shell) - required to observe
# OHMYDEBN_CINNAMON_RESTART_NEEDED, which only propagates back to the
# caller via `source`, not a subprocess. Sets RESTART_FLAG to "1" or "",
# and SCRIPT_STDOUT to whatever the script itself echoed (the min-version
# warning's detail lines are plain `echo`, not the mocked
# ohmydebn-headline call, so they only show up here, not in $CALLS) - a
# marker line separates the flag from that so both can be asserted on.
# OHMYDEBN_CINNAMON_RESTART_NEEDED= clears whatever this var already is in
# the ambient environment before the child bash starts - on a real OhMyDebn
# desktop session it's commonly already exported to 1, and since the script
# under test only ever sets it (never unsets it), an inherited 1 would leak
# straight through and look like a false-positive restart flag on every
# scenario that expects none.
run_script() {
  local output
  output=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" OHMYDEBN_CINNAMON_RESTART_NEEDED= bash -c "
    source '$MOCK_DIR/gtile-restart-patched.sh'
    echo \"GTILE_TEST_FLAG_MARKER:\${OHMYDEBN_CINNAMON_RESTART_NEEDED:-}\"
  " 2>/dev/null)
  RESTART_FLAG=$(echo "$output" | sed -n 's/^GTILE_TEST_FLAG_MARKER://p')
  SCRIPT_STDOUT=$(echo "$output" | grep -v '^GTILE_TEST_FLAG_MARKER:')
}

# Scenario 1: first run ever, gTile installed and enabled -> flags a
# restart and records the version it flagged for.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
DPKG_GTILE_VERSION="2.8.1-20260831" run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "first run, version installed+enabled: restart flagged" "1" "$RESTART_FLAG"
assert_contains "first run: restart headline shown" "$CALLS" "Cinnamon will restart at the end of this update for gtile"
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

# Scenario 5: ohmydebn-gtile not installed at all -> no flag, but the
# min-version warning still fires (installed: none is still "too old").
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_script
CALLS=$(cat "$MOCK_CALLS")
assert_eq "gTile not installed: no restart flag" "" "$RESTART_FLAG"
assert_contains "gTile not installed: out-of-date headline shown" "$CALLS" "WARNING: ohmydebn-gtile is out of date"
assert_contains "gTile not installed: out-of-date detail shown" "$SCRIPT_STDOUT" "Installed: none, need >= 2.3.1"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 6: installed but older than GTILE_MIN_VERSION (2.3.1) -> the
# out-of-date warning fires. This check used to live in
# install/config/cinnamon.sh, which ran before finalization/updates.sh
# actually upgrades packages - moved here (still had zero test coverage
# before this) so it reads the post-upgrade version, not a stale one.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
DPKG_GTILE_VERSION="2.2.1" run_script
CALLS=$(cat "$MOCK_CALLS")
assert_contains "below min version: out-of-date headline shown" "$CALLS" "WARNING: ohmydebn-gtile is out of date"
assert_contains "below min version: out-of-date detail shown" "$SCRIPT_STDOUT" "Installed: 2.2.1, need >= 2.3.1"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 7: installed at/above GTILE_MIN_VERSION -> no warning.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
DPKG_GTILE_VERSION="2.8.1-20260831" run_script
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "at/above min version: no out-of-date headline" "$CALLS" "out of date"
assert_not_contains "at/above min version: no out-of-date detail" "$SCRIPT_STDOUT" "Installed:"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
