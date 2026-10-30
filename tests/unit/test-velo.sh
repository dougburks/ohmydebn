#!/bin/bash
#
# Unit tests for velo's launcher, installer and run payload (bin/ohmydebn-
# velo, -install, -run), the terminal speed test offered beside OhMyDebn's
# own under Trigger > Speed Test. It installs on first use, in the same
# window it then runs in, and the window waits for Enter after velo quits,
# since velo prints the last run's result as it exits. (A failed install
# is covered in test-run-install-failure.sh.)
#
# dpkg answers from MOCK_INSTALLED; sudo, apt, velo and the terminal only
# log; /usr/share/ohmydebn/bin and /usr/bin/velo point at the mock
# directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-velo, -install, -run ==="

setup() {
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && ( -f "$MOCK_DIR/installed" || " ${MOCK_INSTALLED:-} " == *" $2 "* ) ]] && exit 0
exit 1
EOF2
  # apt install marks velo installed, as the real one would.
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$*" == "/usr/bin/apt -y install velo" ]] && touch "$MOCK_DIR/installed"
exit 0
EOF2
  mock_bin velo <<'EOF2'
#!/bin/bash
mock_log "velo${*:+ $*}"
echo "velo: session closed · last run ↓ 495.8 ↑ 495.6 Mbps · 4.0 ms · C"
exit "${MOCK_VELO_EXIT:-0}"
EOF2
  for stub in ohmydebn-show-logo ohmydebn-show-done ohmydebn-terminal; do
    printf '#!/bin/bash\nmock_log "%s${*:+ $*}"\n' "$stub" | mock_bin "$stub"
  done
  for script in ohmydebn-velo ohmydebn-velo-install ohmydebn-velo-run; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/bin/velo#$MOCK_BIN/velo#g" \
      "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
}

run() {
  OUTPUT=$(PATH="$(mock_path)" bash "$MOCK_BIN/$1" <<<"${2:-}" 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

# --- the launcher: one titled terminal running the payload ---
setup
run ohmydebn-velo
assert_eq "launcher: a terminal titled velo, running the payload" \
  "ohmydebn-terminal --title velo -e $MOCK_BIN/ohmydebn-velo-run" "$CALLS"
mock_cleanup

# --- first use: installs from the OhMyDebn repo, then runs in the same window ---
setup
run ohmydebn-velo-run $'\n\n\n'
assert_eq "first use: exits 0" "0" "$STATUS"
assert_contains "first use: asks before installing" "$OUTPUT" "Press Enter to continue or Ctrl-C to cancel."
assert_eq "first use: apt update, install, then velo, then waits" "ohmydebn-show-logo
sudo /usr/bin/apt update
sudo /usr/bin/apt -y install velo
ohmydebn-show-done
velo
ohmydebn-show-done" "$CALLS"
mock_cleanup

# --- installed: runs it, and keeps the result on screen ---
setup
MOCK_INSTALLED=velo run ohmydebn-velo-run $'\n'
assert_not_contains "installed: no install" "$CALLS" "apt"
assert_contains "installed: velo's last result is shown" "$OUTPUT" "last run ↓ 495.8"
assert_eq "installed: waits for Enter after velo quits" "velo
ohmydebn-show-done" "$CALLS"
mock_cleanup

# --- velo fails: the window still waits, so its error can be read ---
setup
MOCK_INSTALLED=velo MOCK_VELO_EXIT=1 run ohmydebn-velo-run $'\n'
assert_eq "velo fails: still waits for Enter" "velo
ohmydebn-show-done" "$CALLS"
mock_cleanup

# --- installer, already installed: nothing to do ---
setup
MOCK_INSTALLED=velo run ohmydebn-velo-install
assert_eq "installer, installed: does nothing" "" "$CALLS"
mock_cleanup

test_summary
