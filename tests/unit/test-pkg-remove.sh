#!/bin/bash
#
# Unit tests for bin/ohmydebn-pkg-remove (Remove > Package) and
# bin/ohmydebn-pkg-install (Install > Package). Remove used to purge the picked packages with `apt -y`, so apt removed them -
# and everything depending on them - without showing the list or asking.
# Now apt shows what it will remove and asks, so it must get the
# terminal's stdin (through xargs it got /dev/null). fzf, dpkg and sudo
# are stand-ins; sudo logs its arguments and the answer it reads. Both
# now say so when apt fails, instead of ending the same way either way.
# Remove also hands the default browser on, in case it just went.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-pkg-remove and bin/ohmydebn-pkg-install ==="

# setup <what fzf returns>
setup() {
  mock_init
  printf '%s' "$1" >"$MOCK_DIR/picked"
  mock_bin dpkg <<'STUB'
#!/bin/bash
printf 'ii  cowsay  1.0  all  x\nii  fortune-mod  1.0  amd64  x\n'
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
[[ "$*" == *"apt update"* ]] && exit 0
read -r answer || answer="<no answer>"
mock_log "sudo $* | answered: $answer"
exit "${MOCK_APT_STATUS:-0}"
STUB
  mock_bin apt <<'STUB'
#!/bin/bash
echo "WARNING: apt does not have a stable CLI interface." >&2
echo "Listing..."
echo "cowsay/stable 1.0 all"
STUB
  # fzf returns the pick, and keeps its choices for the install picker check.
  mock_bin fzf <<'STUB'
#!/bin/bash
cat >"$MOCK_DIR/fzf-input"
cat "$MOCK_DIR/picked"
STUB
  mock_bin ohmydebn-show-done <<'STUB'
#!/bin/bash
mock_log "show-done"
STUB
  mock_bin ohmydebn-browser-set-default <<'STUB'
#!/bin/bash
mock_log "browser-set-default $*"
STUB
  for script in pkg-remove pkg-install; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-$script" >"$MOCK_DIR/$script"
  done
}

setup $'cowsay\nfortune-mod'
PATH="$(mock_path)" bash "$MOCK_DIR/pkg-remove" <<<"n" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "the picked packages are purged by apt" "$CALLS" "sudo /usr/bin/apt purge cowsay fortune-mod"
assert_not_contains "without -y, so apt asks first" "$CALLS" " -y"
assert_contains "apt can read the answer from the terminal" "$CALLS" "answered: n"
assert_contains "a removed default browser is handed on" "$CALLS" "browser-set-default --repair"
assert_eq "the hand-off comes after apt, before the window waits" "sudo browser-set-default show-done" "$(cut -d' ' -f1 "$MOCK_CALLS" | tr '\n' ' ' | sed 's/ $//')"
mock_cleanup

setup ""
PATH="$(mock_path)" bash "$MOCK_DIR/pkg-remove" </dev/null >/dev/null 2>&1
assert_eq "nothing picked: apt isn't run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# apt fails (or the answer was no): the window says the job didn't finish.
setup cowsay
OUTPUT=$(MOCK_APT_STATUS=1 PATH="$(mock_path)" bash "$MOCK_DIR/pkg-remove" <<<"n" 2>&1)
assert_contains "remove: apt failing or answered no is reported" "$OUTPUT" "The removal didn't finish"
OUTPUT=$(PATH="$(mock_path)" bash "$MOCK_DIR/pkg-remove" <<<"y" 2>&1)
assert_not_contains "remove: a removal that worked isn't reported as failed" "$OUTPUT" "didn't finish"
mock_cleanup

setup cowsay
OUTPUT=$(MOCK_APT_STATUS=100 PATH="$(mock_path)" bash "$MOCK_DIR/pkg-install" </dev/null 2>&1)
assert_contains "install: the picked package is installed" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y install cowsay"
assert_contains "install: apt failing is reported" "$OUTPUT" "The install didn't finish"
assert_contains "install: the window still waits to be closed" "$(cat "$MOCK_CALLS")" "show-done"
assert_eq "install: the picker lists packages only, not apt's Listing... header" "cowsay" "$(cat "$MOCK_DIR/fzf-input")"
mock_cleanup

test_summary
