#!/bin/bash
#
# Unit tests for bin/ohmydebn-pkg-remove (Install > Remove Package). It
# used to purge the picked packages with `apt -y`, so apt removed them -
# and everything depending on them - without showing the list or asking.
# Now apt shows what it will remove and asks, so it must get the
# terminal's stdin (through xargs it got /dev/null). fzf, dpkg and sudo
# are stand-ins; sudo logs its arguments and the answer it reads.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-pkg-remove ==="

# setup <what fzf returns>
setup() {
  mock_init
  printf '%s' "$1" >"$MOCK_DIR/picked"
  mock_bin dpkg <<'STUB'
#!/bin/bash
printf 'ii  cowsay  1.0  all  x\nii  fortune-mod  1.0  amd64  x\n'
STUB
  mock_bin fzf <<'STUB'
#!/bin/bash
cat >/dev/null
cat "$MOCK_DIR/picked"
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
read -r answer || answer="<no answer>"
mock_log "sudo $* | answered: $answer"
STUB
  mock_bin ohmydebn-show-done <<'STUB'
#!/bin/bash
mock_log "show-done"
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-pkg-remove" >"$MOCK_DIR/pkg-remove"
}

setup $'cowsay\nfortune-mod'
PATH="$(mock_path)" bash "$MOCK_DIR/pkg-remove" <<<"n" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "the picked packages are purged by apt" "$CALLS" "sudo /usr/bin/apt purge cowsay fortune-mod"
assert_not_contains "without -y, so apt asks first" "$CALLS" " -y"
assert_contains "apt can read the answer from the terminal" "$CALLS" "answered: n"
mock_cleanup

setup ""
PATH="$(mock_path)" bash "$MOCK_DIR/pkg-remove" </dev/null >/dev/null 2>&1
assert_eq "nothing picked: apt isn't run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

test_summary
