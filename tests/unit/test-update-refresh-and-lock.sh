#!/bin/bash
#
# Unit tests for two guards in bin/ohmydebn-update:
#
#  - the self-update refresh: `apt update` runs with
#    APT::Update::Error-Mode=any (plain `apt update` exits 0 even when
#    every source is unreachable), and a failed refresh or a failed
#    `apt install ohmydebn` stops the run with a message BEFORE
#    install.sh - it used to be skipped silently by set -e's and-list
#    rule and the old install.sh ran anyway.
#  - the per-user flock: a second ohmydebn-update while one is running
#    exits 1 with a message and never reaches install.sh.
#
# SAFETY: dpkg is mocked to report ohmydebn INSTALLED here (unlike
# test-update-assume-yes.sh), because the self-update branch is the thing
# under test - so the script's /usr/share/ohmydebn tree is sed-patched to
# a scratch tree whose install.sh only logs, and sudo is a logger that
# simulates apt outcomes via MOCK_APT_UPDATE_EXIT / MOCK_APT_INSTALL_EXIT.
# Logging is opted out (OHMYDEBN_UPDATE_NO_LOG=1) except where the lock is
# proven to work through the wrapper too.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-update"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-update: refresh check and lock ==="

setup() {
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn" ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
case "$*" in
*"apt "*" update"* | *"apt update"*) exit "${MOCK_APT_UPDATE_EXIT:-0}" ;;
*"apt -y install ohmydebn"*) exit "${MOCK_APT_INSTALL_EXIT:-0}" ;;
esac
exit 0
EOF2
  FAKE_HOME="$MOCK_DIR/home"
  FAKE_TREE="$MOCK_DIR/usr-share-ohmydebn"
  RUNTIME="$MOCK_DIR/runtime"
  mkdir -p "$FAKE_HOME" "$FAKE_TREE/bin" "$RUNTIME"
  cat >"$FAKE_TREE/bin/ohmydebn-version" <<'EOF2'
#!/bin/bash
echo 1.2.3
EOF2
  cat >"$FAKE_TREE/bin/ohmydebn-headline" <<'EOF2'
#!/bin/bash
echo "HEADLINE: $1"
EOF2
  cat >"$FAKE_TREE/install.sh" <<'EOF2'
#!/bin/bash
mock_log "install.sh $*"
EOF2
  chmod +x "$FAKE_TREE"/bin/* "$FAKE_TREE/install.sh"
  sed "s#DIR=/usr/share/ohmydebn\$#DIR=$FAKE_TREE#" "$SCRIPT" >"$MOCK_DIR/update-patched.sh"
}

# run_update [extra env assignments...]
run_update() {
  OUTPUT=$(env HOME="$FAKE_HOME" XDG_RUNTIME_DIR="$RUNTIME" PATH="$(mock_path)" OHMYDEBN_UPDATE_NO_LOG=1 "$@" \
    bash "$MOCK_DIR/update-patched.sh" --yes </dev/null 2>&1)
  STATUS=$?
}

# --- happy path: strict refresh, install, then install.sh ---
setup
run_update
assert_eq "happy path: exits 0" "0" "$STATUS"
assert_contains "happy path: refresh runs in strict error mode" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -o APT::Update::Error-Mode=any update"
assert_contains "happy path: self-update installs ohmydebn" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y install ohmydebn"
assert_contains "happy path: install.sh runs" "$(cat "$MOCK_CALLS")" "install.sh"
assert_eq "happy path: lock file records this run's pid and is left in place" "yes" "$([ -s "$RUNTIME/ohmydebn-update-$(id -u).lock" ] && echo yes || echo no)"
mock_cleanup

# --- a failed refresh stops the run before anything changes ---
setup
run_update MOCK_APT_UPDATE_EXIT=100
assert_eq "refresh failure: non-zero exit" "1" "$STATUS"
assert_contains "refresh failure: explains and names the next step" "$OUTPUT" "Could not refresh the package lists - update stopped"
assert_contains "refresh failure: says nothing changed" "$OUTPUT" "Nothing has been changed"
assert_not_contains "refresh failure: no apt install attempted" "$(cat "$MOCK_CALLS")" "apt -y install ohmydebn"
assert_not_contains "refresh failure: install.sh NOT run (the old silent-skip bug)" "$(cat "$MOCK_CALLS")" "install.sh"
mock_cleanup

# --- a failed self-update install stops the run too ---
setup
run_update MOCK_APT_INSTALL_EXIT=100
assert_eq "install failure: non-zero exit" "1" "$STATUS"
assert_contains "install failure: explains" "$OUTPUT" "Could not install the latest ohmydebn package - update stopped"
assert_not_contains "install failure: install.sh NOT run" "$(cat "$MOCK_CALLS")" "install.sh"
mock_cleanup

# --- lock: a second run while one holds the lock is refused ---
setup
LOCK="$RUNTIME/ohmydebn-update-$(id -u).lock"
echo "424242" >"$LOCK"
# Hold the lock from THIS shell on a spare descriptor - flock locks live
# on open file descriptions, so the script's own `flock -n 9` (a fresh
# description on the same file) is refused for as long as fd 8 stays
# open here. No helper process, nothing left running afterwards.
exec 8>>"$LOCK"
flock 8
run_update
assert_eq "locked: exits 1" "1" "$STATUS"
assert_contains "locked: says another update is running" "$OUTPUT" "Another OhMyDebn update is already running"
assert_contains "locked: names the holder's pid from the lock file" "$OUTPUT" "Started by process 424242"
assert_not_contains "locked: no apt calls" "$(cat "$MOCK_CALLS")" "sudo"
assert_not_contains "locked: install.sh NOT run" "$(cat "$MOCK_CALLS")" "install.sh"
# ...and once released, the same run goes through.
exec 8>&-
: >"$MOCK_CALLS"
run_update
assert_eq "released: exits 0" "0" "$STATUS"
assert_contains "released: install.sh runs" "$(cat "$MOCK_CALLS")" "install.sh"
mock_cleanup

# --- lock works through the logging wrapper too (lock taken by the inner run, not contended by the outer) ---
setup
OUTPUT=$(env HOME="$FAKE_HOME" XDG_RUNTIME_DIR="$RUNTIME" PATH="$(mock_path)" bash "$MOCK_DIR/update-patched.sh" --yes </dev/null 2>&1)
STATUS=$?
assert_eq "logged run: exits 0 (the wrapper's re-exec does not contend with itself)" "0" "$STATUS"
assert_contains "logged run: install.sh runs" "$(cat "$MOCK_CALLS")" "install.sh"
assert_contains "logged run: was actually logged" "$OUTPUT" "Logging this update to"
mock_cleanup

# --- lock dir fallback: an unusable XDG_RUNTIME_DIR falls back to /tmp without failing ---
setup
run_update XDG_RUNTIME_DIR=/definitely/not/a/dir
assert_eq "runtime dir fallback: still runs" "0" "$STATUS"
assert_eq "runtime dir fallback: lock landed in /tmp" "yes" "$([ -e "/tmp/ohmydebn-update-$(id -u).lock" ] && echo yes || echo no)"
mock_cleanup

test_summary
