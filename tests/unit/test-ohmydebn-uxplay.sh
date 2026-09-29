#!/bin/bash
#
# Unit tests for bin/ohmydebn-uxplay (Apps > Media > UxPlay). It ran plain
# `uxplay`, which picks random ports on every run - ports ufw's default
# deny-incoming blocks, and not the ones media.md says to open. It must
# pin UxPlay to 6000-6002 with -p 6000, and install UxPlay first only when
# it's missing. dpkg and the terminal launchers are mocked.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-uxplay ==="

setup() {
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "uxplay" && -f "$MOCK_DIR/installed" ]] && exit 0
exit 1
EOF2
  mock_bin ohmydebn-launch-floating-terminal <<'EOF2'
#!/bin/bash
mock_log "terminal title=$1 cmd=$2"
EOF2
  mock_bin ohmydebn-launch-floating-terminal-with-presentation <<'EOF2'
#!/bin/bash
mock_log "install $*"
touch "$MOCK_DIR/installed"
EOF2
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-uxplay" >"$MOCK_DIR/uxplay.sh"
}

# --- installed: runs UxPlay on the documented ports ---
setup
touch "$MOCK_DIR/installed"
PATH="$(mock_path)" bash "$MOCK_DIR/uxplay.sh" </dev/null >/dev/null 2>&1
assert_eq "installed: runs uxplay -p 6000 (ports 6000-6002)" "terminal title=UxPlay cmd=uxplay -p 6000" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- not installed: installs it first, then runs it the same way ---
setup
PATH="$(mock_path)" bash "$MOCK_DIR/uxplay.sh" </dev/null >/dev/null 2>&1
assert_contains "not installed: installs first" "$(cat "$MOCK_CALLS")" "install UxPlay"
assert_contains "not installed: then runs uxplay -p 6000" "$(cat "$MOCK_CALLS")" "terminal title=UxPlay cmd=uxplay -p 6000"
mock_cleanup

test_summary
