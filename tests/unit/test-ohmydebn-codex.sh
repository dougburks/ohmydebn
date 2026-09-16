#!/bin/bash
#
# Unit tests for the Codex (OpenAI CLI coding agent) wrappers -
# bin/ohmydebn-codex-cli, bin/ohmydebn-codex-run and
# bin/ohmydebn-codex-install - which mirror Pi's. The package
# (ohmydebn-codex-cli) installs no /usr/bin symlink, only
# /usr/lib/ohmydebn-codex-cli/bin/codex, so both runners must exec that
# exact path; -cli must forward its args; -run must start each session in
# a fresh ~/codex-sessions directory; and both must install on demand
# first when the package is missing. dpkg/sudo/apt and the binary itself
# are mocked, and the absolute binary path is sed-patched to the mock, so
# nothing here touches the real system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-codex-cli / ohmydebn-codex-run / ohmydebn-codex-install ==="

CODEX_BIN=/usr/lib/ohmydebn-codex-cli/bin/codex

# setup <installed: yes|no>
setup() {
  local installed="$1"
  mock_init
  mock_bin dpkg <<EOF2
#!/bin/bash
[[ "\$1" == "-s" && "\$2" == "ohmydebn-codex-cli" && "$installed" == "yes" ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
exit 0
EOF2
  mock_bin codex <<'EOF2'
#!/bin/bash
mock_log "codex $* (cwd=$PWD)"
exit 0
EOF2
  for helper in ohmydebn-show-logo ohmydebn-show-done; do
    mock_bin "$helper" <<EOF2
#!/bin/bash
mock_log "$helper"
EOF2
  done
  SCRATCH_HOME=$(mktemp -d)
  for script in ohmydebn-codex-cli ohmydebn-codex-run ohmydebn-codex-install; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#$CODEX_BIN#$MOCK_BIN/codex#g" "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# --- installed: -cli execs the binary with its args, no install attempt ---
setup yes
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-codex-cli" --model gpt-5 "fix the bug" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "installed: -cli execs the packaged binary with its args forwarded" "$CALLS" "codex --model gpt-5 fix the bug"
assert_not_contains "installed: -cli does not run apt" "$CALLS" "sudo"
teardown

# --- installed: -run starts a fresh session dir under ~/codex-sessions and execs there ---
setup yes
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-codex-run" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "installed: -run execs the packaged binary" "$CALLS" "codex  (cwd=$SCRATCH_HOME/codex-sessions/session-"
assert_eq "installed: -run created exactly one session directory" "1" "$(find "$SCRATCH_HOME/codex-sessions" -mindepth 1 -maxdepth 1 -type d -name 'session-*' | wc -l)"
assert_not_contains "installed: -run shows no install logo" "$CALLS" "ohmydebn-show-logo"
teardown

# --- not installed: -install (no prompt) runs apt update then installs the package ---
setup no
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-codex-install" --skip-prompt >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "not installed: -install --skip-prompt runs apt update" "$CALLS" "sudo /usr/bin/apt update"
assert_contains "not installed: -install installs ohmydebn-codex-cli" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-codex-cli"
teardown

# --- installed: -install is a no-op ---
setup yes
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-codex-install" --skip-prompt >/dev/null 2>&1
assert_eq "installed: -install does nothing" "" "$(cat "$MOCK_CALLS")"
teardown

# --- not installed: -run installs first (logo/done framing), then does not exec since dpkg still says missing ---
setup no
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-codex-run" < <(printf '\n') >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "not installed: -run shows the logo, installs, shows done" "$CALLS" "ohmydebn-show-logo"
assert_contains "not installed: -run runs the install" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-codex-cli"
assert_contains "not installed: -run finishes the framing" "$CALLS" "ohmydebn-show-done"
assert_not_contains "not installed: -run does not exec a binary that isn't there" "$CALLS" "codex "
teardown

test_summary
