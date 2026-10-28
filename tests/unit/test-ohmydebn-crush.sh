#!/bin/bash
#
# Unit tests for Crush, Charm's terminal coding agent: bin/ohmydebn-crush
# (the launcher), -run, -cli, -install and -remove. Crush comes from the
# OhMyDebn repo, where ohmydebn-package-build republishes Charm's own
# package, as it does gum, so installing it adds no third-party repo.
#
# sudo, apt and crush only log (apt install marks crush installed); dpkg
# answers from that install marker or MOCK_INSTALLED.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-crush, -run, -cli, -install, -remove ==="

setup() {
  mock_init
  mkdir -p "$MOCK_DIR/home"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && ( -f "$MOCK_DIR/installed" || " ${MOCK_INSTALLED:-} " == *" $2 "* ) ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$*" == "/usr/bin/apt -y install crush" ]] && touch "$MOCK_DIR/installed"
exit 0
EOF2
  mock_bin crush <<'EOF2'
#!/bin/bash
mock_log "crush${*:+ $*} in ${PWD/#"$HOME"/"~"}"
EOF2
  for stub in ohmydebn-show-logo ohmydebn-show-done ohmydebn-terminal ohmydebn-ai-set-default; do
    printf '#!/bin/bash\nmock_log "%s${*:+ $*}"\n' "$stub" | mock_bin "$stub"
  done
  for script in ohmydebn-crush ohmydebn-crush-run ohmydebn-crush-cli ohmydebn-crush-install ohmydebn-crush-remove; do
    sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/bin/crush#$MOCK_BIN/crush#g" \
      "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
}

# run <script> [stdin] [args...]
run() {
  local script="$1" input="${2:-}"
  shift 2 2>/dev/null || shift
  OUTPUT=$(HOME="$MOCK_DIR/home" PATH="$(mock_path)" bash "$MOCK_BIN/$script" "$@" <<<"$input" 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

# --- the launcher: one titled terminal running the payload ---
setup
run ohmydebn-crush
assert_eq "launcher: a terminal titled Crush (its tile rule's title), running the payload" \
  "ohmydebn-terminal --title Crush -e $MOCK_BIN/ohmydebn-crush-run" "$CALLS"
mock_cleanup

# --- first install: from the OhMyDebn repo, nothing else added ---
setup
run ohmydebn-crush-install $'\n'
assert_eq "install: exits 0" "0" "$STATUS"
assert_contains "install: asks before changing anything" "$OUTPUT" "Press Enter to continue or Ctrl-C to cancel."
assert_eq "install: refreshes apt, installs crush, asks about the default" "sudo /usr/bin/apt update
sudo /usr/bin/apt -y install crush
ohmydebn-ai-set-default --ask crush" "$CALLS"
mock_cleanup

# --- --skip-prompt: asks nothing ---
setup
run ohmydebn-crush-install "" --skip-prompt
assert_eq "--skip-prompt: exits 0" "0" "$STATUS"
assert_not_contains "--skip-prompt: no Enter prompt" "$OUTPUT" "Press Enter"
assert_not_contains "--skip-prompt: no default-agent question" "$CALLS" "ohmydebn-ai-set-default"
mock_cleanup

# --- already installed: nothing to do ---
setup
MOCK_INSTALLED=crush run ohmydebn-crush-install
assert_eq "installed: installer does nothing" "" "$CALLS"
mock_cleanup

# --- the run payload: installs on first use, then runs in a fresh session folder ---
setup
run ohmydebn-crush-run $'\n'
assert_eq "first use: exits 0" "0" "$STATUS"
assert_contains "first use: installs crush" "$CALLS" "sudo /usr/bin/apt -y install crush"
assert_eq "first use: then runs it in a new ~/crush-sessions folder" "yes" \
  "$(tail -1 "$MOCK_CALLS" | grep -qE '^crush in ~/crush-sessions/session-[A-Za-z0-9]{6}$' && echo yes || echo no)"
mock_cleanup
setup
MOCK_INSTALLED=crush run ohmydebn-crush-run
assert_eq "installed: just runs it" "yes" \
  "$(grep -qE '^crush in ~/crush-sessions/session-' <<<"$CALLS" && [ "$(wc -l <<<"$CALLS")" = 1 ] && echo yes || echo no)"
mock_cleanup

# --- the -cli companion: runs in the current folder, passing its arguments ---
setup
MOCK_INSTALLED=crush run ohmydebn-crush-cli "" run "fix the tests"
assert_eq "cli: passes its arguments, in the current folder" "crush run fix the tests in $PWD" "$CALLS"
mock_cleanup

# --- remove: purges it, keeping the user's settings ---
setup
MOCK_INSTALLED=crush run ohmydebn-crush-remove $'\n'
assert_eq "remove: exits 0" "0" "$STATUS"
assert_contains "remove: says settings are kept" "$OUTPUT" "settings and sessions are"
assert_eq "remove: refreshes apt, purges crush, autoremoves" "sudo /usr/bin/apt update
sudo /usr/bin/apt -y purge crush
sudo /usr/bin/apt -y autoremove" "$CALLS"
mock_cleanup
setup
run ohmydebn-crush-remove
assert_contains "remove, not installed: says so" "$OUTPUT" "Crush is not currently installed."
assert_eq "remove, not installed: does nothing" "" "$CALLS"
mock_cleanup

test_summary
