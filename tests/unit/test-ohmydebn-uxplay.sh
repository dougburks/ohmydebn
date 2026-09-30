#!/bin/bash
#
# Unit tests for UxPlay (Apps > Media): bin/ohmydebn-uxplay,
# ohmydebn-uxplay-install and ohmydebn-uxplay-installed.
#
# - The launcher ran plain `uxplay`, which picks random ports on every run -
#   ports ufw's default deny-incoming blocks, and not the ones media.md
#   says to open. It must pin UxPlay to 6000-6002 with -p 6000.
# - Debian's uxplay package pulls in none of the GStreamer plugins UxPlay's
#   README requires except libav, so on Linux Mint it wouldn't start until
#   gstreamer1.0-plugins-bad was installed by hand. Installed has to mean
#   uxplay plus those plugins, so a UxPlay installed earlier without them
#   is repaired the next time it's opened.
#
# dpkg, apt, sudo and the terminal launchers are mocked; installed packages
# are the lines of a scratch file.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-uxplay and its installer ==="

ALL="uxplay gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-x"

# setup <installed package>...
setup() {
  mock_init
  printf '%s\n' "$@" >"$MOCK_DIR/installed"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" ]] && grep -qxF "$2" "$MOCK_DIR/installed" && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
exec "$@"
EOF2
  mock_bin apt <<'EOF2'
#!/bin/bash
mock_log "apt $*"
if [[ "$1" == "-y" && "$2" == "install" ]]; then
  shift 2
  printf '%s\n' "$@" >>"$MOCK_DIR/installed"
fi
EOF2
  mock_bin ohmydebn-launch-floating-terminal <<'EOF2'
#!/bin/bash
mock_log "terminal title=$1 cmd=$2"
EOF2
  # The installer runs for real, answering its prompt with Enter.
  mock_bin ohmydebn-launch-floating-terminal-with-presentation <<'EOF2'
#!/bin/bash
mock_log "presentation $1"
"$2" <<<""
EOF2
  for script in ohmydebn-uxplay ohmydebn-uxplay-install ohmydebn-uxplay-installed; do
    sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/bin/apt#$MOCK_BIN/apt#g" \
      "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
}

run_launcher() {
  PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-uxplay" </dev/null >"$MOCK_DIR/out" 2>&1
}

# --- everything installed: runs UxPlay on the documented ports, installs nothing ---
# shellcheck disable=SC2086
setup $ALL
run_launcher
assert_eq "installed: runs uxplay -p 6000 (ports 6000-6002)" "terminal title=UxPlay cmd=uxplay -p 6000" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- nothing installed: installs uxplay and every plugin, then runs it ---
setup
run_launcher
assert_contains "not installed: installs uxplay and the plugins" "$(cat "$MOCK_CALLS")" "apt -y install $ALL"
assert_contains "not installed: then runs uxplay -p 6000" "$(cat "$MOCK_CALLS")" "terminal title=UxPlay cmd=uxplay -p 6000"
mock_cleanup

# --- uxplay installed without the plugins (Mint): only the plugins are added ---
setup uxplay gstreamer1.0-plugins-base
run_launcher
assert_contains "no plugins: the installer runs" "$(cat "$MOCK_CALLS")" "presentation UxPlay"
assert_contains "no plugins: installs just what's missing" "$(cat "$MOCK_CALLS")" \
  "apt -y install gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-x"
assert_contains "no plugins: then runs uxplay" "$(cat "$MOCK_CALLS")" "terminal title=UxPlay cmd=uxplay -p 6000"
mock_cleanup

# --- ohmydebn-uxplay-installed --missing lists exactly what's missing ---
setup uxplay gstreamer1.0-plugins-good
OUT=$(PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-uxplay-installed" --missing)
assert_eq "--missing: one per line" "$(printf 'gstreamer1.0-plugins-base\ngstreamer1.0-plugins-bad\ngstreamer1.0-x')" "$OUT"
mock_cleanup

test_summary
