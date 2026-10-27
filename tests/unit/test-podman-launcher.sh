#!/bin/bash
#
# Unit tests for bin/ohmydebn-podman, the Podman menu entry and hotkey. The
# subordinate ID backfill (ohmydebn-podman-subids-ensure) may need sudo, so
# it must run inside the terminal the launcher opens: run from the menu
# directly, with no terminal for sudo to ask in, it failed and the
# launcher exited before opening anything. Everything it calls is a
# stand-in that logs its arguments.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-podman ==="

setup() {
  mock_init
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  mock_bin ohmydebn-podman-installed <<'EOF2'
#!/bin/bash
[[ " ${MOCK_INSTALLED:-} " == *" podman "* ]]
EOF2
  # Fails like it did without a terminal for sudo, so a direct call would
  # stop the launcher (set -e) before it opened the terminal.
  mock_bin ohmydebn-podman-subids-ensure <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-podman-subids-ensure $*"
exit 1
EOF2
  for stub in ohmydebn-launch-floating-terminal ohmydebn-launch-floating-terminal-with-presentation; do
    mock_bin "$stub" <<EOF2
#!/bin/bash
mock_log "$stub \$*"
EOF2
  done
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-podman" >"$MOCK_DIR/podman"
}
run() { PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" bash "$MOCK_DIR/podman" </dev/null >/dev/null 2>&1; }

setup
MOCK_INSTALLED="podman" run
CALLS=$(cat "$MOCK_CALLS")
assert_eq "installed: the subid backfill isn't run outside a terminal" "0" "$(grep -c '^ohmydebn-podman-subids-ensure' "$MOCK_CALLS")"
assert_contains "installed: the terminal opens even when the backfill would fail" "$CALLS" "ohmydebn-launch-floating-terminal Podman"
assert_contains "installed: the terminal runs the backfill first, then --help" "$CALLS" \
  "ohmydebn-launch-floating-terminal Podman $MOCK_BIN/ohmydebn-podman-subids-ensure; podman --help; exec bash"
mock_cleanup

setup
MOCK_INSTALLED="" run
CALLS=$(cat "$MOCK_CALLS")
assert_contains "not installed: the installer is offered" "$CALLS" "ohmydebn-launch-floating-terminal-with-presentation Podman"
assert_not_contains "not installed (and the install declined): no Podman terminal" "$CALLS" "ohmydebn-launch-floating-terminal Podman"
mock_cleanup

test_summary
