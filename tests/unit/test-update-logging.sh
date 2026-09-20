#!/bin/bash
#
# Unit tests for bin/ohmydebn-update's run logging: every run re-execs
# itself under `script` so the whole session lands in
# ~/.local/state/ohmydebn-logs/update-<stamp>.log (with update-latest.log
# pointing at it), the child's exit status still comes back through the
# wrapper, only the newest KEEP_LOGS runs are kept, the inner run never
# wraps itself a second time, and OHMYDEBN_UPDATE_NO_LOG=1 opts out.
#
# SAFETY: same arrangement as test-update-assume-yes.sh - dpkg is mocked
# to report ohmydebn NOT installed (routing the script to a scratch
# $HOME/.local/share/ohmydebn tree and skipping the apt self-update),
# sudo is a pure logger, so nothing here touches the real system. The
# real util-linux `script` is used, since the wrapping is the thing under
# test.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-update"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-update: run logging ==="

# setup [install.sh exit code]
setup() {
  local install_exit="${1:-0}"
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF2
  FAKE_HOME="$MOCK_DIR/home"
  FAKE_TREE="$FAKE_HOME/.local/share/ohmydebn"
  LOG_DIR="$FAKE_HOME/.local/state/ohmydebn-logs"
  mkdir -p "$FAKE_TREE/bin"
  cat >"$FAKE_TREE/bin/ohmydebn-version" <<'EOF2'
#!/bin/bash
echo 1.2.3
EOF2
  cat >"$FAKE_TREE/bin/ohmydebn-headline" <<'EOF2'
#!/bin/bash
echo "HEADLINE: $1"
EOF2
  cat >"$FAKE_TREE/install.sh" <<EOF2
#!/bin/bash
echo "install.sh ran with: \$*"
echo "log seen by install.sh: \${OHMYDEBN_UPDATE_LOG:-unset}"
exit $install_exit
EOF2
  chmod +x "$FAKE_TREE"/bin/* "$FAKE_TREE/install.sh"
}

run_update() {
  OUTPUT=$(HOME="$FAKE_HOME" PATH="$(mock_path)" bash "$SCRIPT" --yes </dev/null 2>&1)
  STATUS=$?
}

# --- a run is logged, announced, and the latest symlink follows it ---
setup
run_update
assert_eq "logged run: exits 0" "0" "$STATUS"
LOGS=("$LOG_DIR"/update-[0-9]*.log)
assert_eq "logged run: exactly one log file created" "1" "${#LOGS[@]}"
assert_contains "logged run: announces the log path on the terminal" "$OUTPUT" "Logging this update to:"
assert_contains "logged run: log path on its own line" "$OUTPUT" "
$LOG_DIR/update-"
assert_contains "logged run: log holds the version headline" "$(cat "${LOGS[0]}")" "current OhMyDebn version: 1.2.3"
assert_contains "logged run: log holds install.sh's output" "$(cat "${LOGS[0]}")" "install.sh ran with:"
assert_contains "logged run: install.sh sees the log path in its environment" "$(cat "${LOGS[0]}")" "log seen by install.sh: $LOG_DIR/update-"
assert_eq "logged run: update-latest.log points at the new log" "${LOGS[0]}" "$(readlink "$LOG_DIR/update-latest.log")"
assert_contains "logged run: install.sh still invoked exactly once (no double wrap)" "$(grep -c 'install.sh ran with' "${LOGS[0]}")" "1"
mock_cleanup

# --- the child's exit status comes back through the wrapper ---
setup 3
run_update
assert_eq "exit status: install.sh's 3 propagates through script" "3" "$STATUS"
mock_cleanup

# --- rotation keeps the newest KEEP_LOGS (10), never the symlink ---
setup
mkdir -p "$LOG_DIR"
for i in $(seq 1 12); do
  f="$LOG_DIR/update-2026010100$(printf '%02d' "$i")00.log"
  echo "old $i" >"$f"
  touch -d "2026-01-01 00:$(printf '%02d' "$i"):00" "$f"
done
run_update
REMAINING=("$LOG_DIR"/update-[0-9]*.log)
assert_eq "rotation: exactly 10 logs remain after the run" "10" "${#REMAINING[@]}"
assert_eq "rotation: the three oldest were removed" "no" \
  "$([ -e "$LOG_DIR/update-20260101000100.log" ] || [ -e "$LOG_DIR/update-20260101000200.log" ] || [ -e "$LOG_DIR/update-20260101000300.log" ] && echo yes || echo no)"
assert_eq "rotation: the newest old log survived" "yes" "$([ -e "$LOG_DIR/update-20260101001200.log" ] && echo yes || echo no)"
assert_eq "rotation: update-latest.log symlink still present" "yes" "$([ -L "$LOG_DIR/update-latest.log" ] && echo yes || echo no)"
mock_cleanup

# --- opt-out: no log directory, no wrapping, update still runs ---
setup
OUTPUT=$(HOME="$FAKE_HOME" PATH="$(mock_path)" OHMYDEBN_UPDATE_NO_LOG=1 bash "$SCRIPT" --yes </dev/null 2>&1)
STATUS=$?
assert_eq "opt-out: exits 0" "0" "$STATUS"
assert_eq "opt-out: no log directory created" "no" "$([ -d "$LOG_DIR" ] && echo yes || echo no)"
assert_not_contains "opt-out: no log announcement" "$OUTPUT" "Logging this update"
assert_contains "opt-out: install.sh still ran" "$OUTPUT" "install.sh ran with:"
mock_cleanup

# --- an already-logged (inner) run never wraps itself again ---
setup
OUTPUT=$(HOME="$FAKE_HOME" PATH="$(mock_path)" OHMYDEBN_UPDATE_LOG=/somewhere/outer.log bash "$SCRIPT" --yes </dev/null 2>&1)
STATUS=$?
assert_eq "inner run: exits 0" "0" "$STATUS"
assert_eq "inner run: creates no log of its own" "no" "$([ -d "$LOG_DIR" ] && echo yes || echo no)"
assert_contains "inner run: reports the outer log path" "$OUTPUT" "Logging this update to:
/somewhere/outer.log"
mock_cleanup

test_summary
