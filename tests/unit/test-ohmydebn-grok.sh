#!/bin/bash
#
# Unit tests for the Grok Build (xAI CLI coding agent) wrappers -
# bin/ohmydebn-grok-cli, bin/ohmydebn-grok-run and bin/ohmydebn-grok-install
# - which mirror Codex's. The package (ohmydebn-grok-build) installs no
# /usr/bin symlink, only /usr/lib/ohmydebn-grok-build/grok, so both runners
# must exec that exact path, with Grok's own self-updater switched off
# (apt updates it); -cli must forward its args; -run must start each
# session in a fresh ~/grok-sessions directory; and -install must set up
# Grok's terminal theme only when the user has no Grok config yet, and ask
# about the default AI assistant unless run with --skip-prompt. dpkg/sudo/
# apt and the binary itself are mocked, and the absolute binary path is
# sed-patched to the mock, so nothing here touches the real system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-grok-cli / ohmydebn-grok-run / ohmydebn-grok-install ==="

GROK_BIN=/usr/lib/ohmydebn-grok-build/grok

# setup <installed: yes|no|after-apt>
setup() {
  local installed="$1"
  mock_init
  [[ "$installed" == "yes" ]] && touch "$MOCK_DIR/installed"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn-grok-build" && -f "$MOCK_DIR/installed" ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<EOF2
#!/bin/bash
mock_log "sudo \$*"
[[ "$installed" == "after-apt" && "\$*" == *"install ohmydebn-grok-build"* ]] && touch "\$MOCK_DIR/installed"
exit 0
EOF2
  mock_bin grok <<'EOF2'
#!/bin/bash
mock_log "grok $* (cwd=$PWD) (autoupdater-off=${GROK_DISABLE_AUTOUPDATER:-})"
exit 0
EOF2
  for helper in ohmydebn-show-logo ohmydebn-show-done; do
    mock_bin "$helper" <<EOF2
#!/bin/bash
mock_log "$helper"
EOF2
  done
  mock_bin ohmydebn-ai-set-default <<'EOF2'
#!/bin/bash
mock_log "ai-set-default $*"
EOF2
  SCRATCH_HOME=$(mktemp -d)
  for script in ohmydebn-grok-cli ohmydebn-grok-run ohmydebn-grok-install; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#$GROK_BIN#$MOCK_BIN/grok#g" "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/$1" "${@:2}"
}

GROK_CONFIG() { echo "$SCRATCH_HOME/.grok/config.toml"; }

# --- installed: -cli execs the binary with its args, updater off, no install attempt ---
setup yes
run ohmydebn-grok-cli --continue "fix the bug" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "installed: -cli execs the packaged binary with its args forwarded" "$CALLS" "grok --continue fix the bug"
assert_contains "installed: -cli turns off Grok's self-updater" "$CALLS" "(autoupdater-off=1)"
assert_not_contains "installed: -cli does not run apt" "$CALLS" "sudo"
teardown

# --- installed: -run starts a fresh session dir under ~/grok-sessions and execs there ---
setup yes
run ohmydebn-grok-run >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "installed: -run execs the packaged binary" "$CALLS" "grok  (cwd=$SCRATCH_HOME/grok-sessions/session-"
assert_contains "installed: -run turns off Grok's self-updater" "$CALLS" "(autoupdater-off=1)"
assert_eq "installed: -run created exactly one session directory" "1" "$(find "$SCRATCH_HOME/grok-sessions" -mindepth 1 -maxdepth 1 -type d -name 'session-*' | wc -l)"
assert_not_contains "installed: -run shows no install logo" "$CALLS" "ohmydebn-show-logo"
teardown

# --- not installed, from the menu: installs, themes, asks about the default ---
setup after-apt
OUT=$(printf '\n' | run ohmydebn-grok-install 2>&1)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "menu install: explains the subscription or API key" "$OUT" "SuperGrok or X Premium+ subscription"
assert_contains "menu install: runs apt update" "$CALLS" "sudo /usr/bin/apt update"
assert_contains "menu install: installs ohmydebn-grok-build" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-grok-build"
assert_contains "menu install: asks about the default AI assistant" "$CALLS" "ai-set-default --ask grok"
assert_contains "menu install: follows the terminal theme" "$(cat "$(GROK_CONFIG)")" 'theme = "terminal"'
assert_contains "menu install: enables the terminal-theme feature flag" "$(cat "$(GROK_CONFIG)")" "terminal_theme = true"
teardown

# --- --skip-prompt: installs and themes, never asks ---
setup after-apt
run ohmydebn-grok-install --skip-prompt </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "--skip-prompt: installs" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-grok-build"
assert_not_contains "--skip-prompt: never asks about the default" "$CALLS" "ai-set-default"
teardown

# --- an existing Grok config is never overwritten ---
setup after-apt
mkdir -p "$SCRATCH_HOME/.grok"
printf '[ui]\ntheme = "grokday"\n' >"$(GROK_CONFIG)"
run ohmydebn-grok-install --skip-prompt </dev/null >/dev/null 2>&1
assert_eq "existing config: left exactly as it was" "$(printf '[ui]\ntheme = "grokday"')" "$(cat "$(GROK_CONFIG)")"
teardown

# --- installed: -install is a no-op ---
setup yes
run ohmydebn-grok-install --skip-prompt >/dev/null 2>&1
assert_eq "installed: -install does nothing" "" "$(cat "$MOCK_CALLS")"
assert_eq "installed: -install writes no config" "no" "$([[ -e "$(GROK_CONFIG)" ]] && echo yes || echo no)"
teardown

# --- not installed: -run installs first (logo/done framing), then does not exec since dpkg still says missing ---
setup no
run ohmydebn-grok-run < <(printf '\n') >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "not installed: -run shows the logo, installs, shows done" "$CALLS" "ohmydebn-show-logo"
assert_contains "not installed: -run runs the install" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-grok-build"
assert_contains "not installed: -run finishes the framing" "$CALLS" "ohmydebn-show-done"
assert_not_contains "not installed: -run does not exec a binary that isn't there" "$CALLS" "grok  (cwd"
teardown

test_summary
