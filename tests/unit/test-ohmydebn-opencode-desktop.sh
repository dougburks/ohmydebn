#!/bin/bash
#
# Unit tests for OpenCode Desktop, OpenCode's GUI app: bin/ohmydebn-
# opencode-desktop (the launcher), -install and -remove, and its Apps > AI
# item. It comes from the OhMyDebn repo as package opencode (OpenCode's own,
# without its self-updater), installed in a window of its own the first
# time it's opened, as Claude Desktop is.
#
# sudo, apt, the install window and the app only log (apt install marks
# opencode installed); dpkg answers from that marker or MOCK_INSTALLED;
# MOCK_ARCH is what dpkg --print-architecture says (amd64 by default).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-opencode-desktop, -install, -remove ==="

setup() {
  mock_init
  mkdir -p "$MOCK_DIR/home"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "--print-architecture" ]] && { echo "${MOCK_ARCH:-amd64}"; exit 0; }
[[ "$1" == "-s" && ( -f "$MOCK_DIR/installed" || " ${MOCK_INSTALLED:-} " == *" $2 "* ) ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$*" == "/usr/bin/apt -y install opencode" ]] && touch "$MOCK_DIR/installed"
exit 0
EOF2
  mock_bin ai.opencode <<'EOF2'
#!/bin/bash
mock_log "ai.opencode${*:+ $*}"
EOF2
  # The install window runs its command, as the real one does in a terminal,
  # where the user presses Enter at its prompt.
  mock_bin ohmydebn-launch-floating-terminal-with-presentation <<'EOF2'
#!/bin/bash
mock_log "install window: $1"
"$2" <<<""
EOF2
  printf '#!/bin/bash\nmock_log "ohmydebn-ai-set-default${*:+ $*}"\n' | mock_bin ohmydebn-ai-set-default
  for script in ohmydebn-opencode-desktop ohmydebn-opencode-desktop-install ohmydebn-opencode-desktop-remove; do
    sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/opt/OpenCode/ai.opencode#$MOCK_BIN/ai.opencode#g" \
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

# --- installed: the launcher just opens the app ---
setup
MOCK_INSTALLED=opencode run ohmydebn-opencode-desktop
assert_eq "installed: opens the app" "ai.opencode" "$CALLS"
mock_cleanup

# --- first use: installs in a window titled for its tile rule, then opens ---
setup
run ohmydebn-opencode-desktop
assert_eq "first use: exits 0" "0" "$STATUS"
assert_eq "first use: install window, apt, then the app" "install window: OpenCode Desktop
sudo /usr/bin/apt update
sudo /usr/bin/apt -y install opencode
ohmydebn-ai-set-default --ask opencode-desktop
ai.opencode" "$CALLS"
mock_cleanup

# --- the installer: asks first, unless --skip-prompt ---
setup
run ohmydebn-opencode-desktop-install $'\n'
assert_contains "install: asks before changing anything" "$OUTPUT" "Press Enter to continue or Ctrl-C to cancel."
assert_contains "install: from the OhMyDebn repo" "$CALLS" "sudo /usr/bin/apt -y install opencode"
mock_cleanup
setup
run ohmydebn-opencode-desktop-install "" --skip-prompt
assert_not_contains "--skip-prompt: no Enter prompt" "$OUTPUT" "Press Enter"
assert_not_contains "--skip-prompt: no default-agent question" "$CALLS" "ohmydebn-ai-set-default"
assert_contains "--skip-prompt: still installs" "$CALLS" "apt -y install opencode"
mock_cleanup

# --- only x86_64 and arm64 builds exist ---
setup
MOCK_ARCH=armhf run ohmydebn-opencode-desktop-install $'\n'
assert_eq "armhf: refused" "1" "$STATUS"
assert_contains "armhf: says why" "$OUTPUT" "only available for x86_64 and arm64"
assert_not_contains "armhf: apt not run" "$CALLS" "apt"
mock_cleanup

# --- installed already: the installer does nothing ---
setup
MOCK_INSTALLED=opencode run ohmydebn-opencode-desktop-install
assert_eq "installed: installer does nothing" "" "$CALLS"
mock_cleanup

# --- remove: purges the app, keeping OpenCode's data and the terminal app ---
setup
MOCK_INSTALLED=opencode run ohmydebn-opencode-desktop-remove $'\n'
assert_contains "remove: says what's kept" "$OUTPUT" "settings and"
assert_eq "remove: purges only the opencode package" "sudo /usr/bin/apt update
sudo /usr/bin/apt -y purge opencode
sudo /usr/bin/apt -y autoremove" "$CALLS"
mock_cleanup
setup
run ohmydebn-opencode-desktop-remove
assert_contains "remove, not installed: says so" "$OUTPUT" "OpenCode Desktop is not currently installed."
assert_eq "remove, not installed: does nothing" "" "$CALLS"
mock_cleanup

# --- Apps > AI: its item opens it, and OpenCode's opens the terminal app ---
# (*OpenCode* would match both labels; the arm for this one comes first.)
mock_init
INDEX=$(HOME="$MOCK_DIR" bash -c 'source "$1"; menu_tree_flatten "$2"' _ \
  "$REPO_ROOT/bin/ohmydebn-menu-tree" "$REPO_ROOT/bin/ohmydebn-menu" 2>/dev/null)
assert_eq "menu: the desktop app's item opens it" "/usr/share/ohmydebn/bin/ohmydebn-opencode-desktop" \
  "$(grep -F 'Apps > AI > OpenCode App' <<<"$INDEX" | cut -f2)"
assert_eq "menu: OpenCode's own item still opens the terminal app" "/usr/share/ohmydebn/bin/ohmydebn-opencode" \
  "$(grep -F 'Apps > AI > OpenCode (' <<<"$INDEX" | cut -f2)"
mock_cleanup

test_summary
