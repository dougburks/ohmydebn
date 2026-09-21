#!/bin/bash
#
# Unit tests for bin/ohmydebn-podman-subids-ensure. Rootless podman needs
# subordinate UID/GID ranges for the user in /etc/subuid and /etc/subgid;
# Devuan's installer (and any other that creates the user before those
# files exist) leaves them out, so the first SO-CRATES pull died on
# "lchown /etc/gshadow: invalid argument". These tests run the real script
# against scratch copies of both files with sudo/usermod/getent/podman
# stubbed, covering: nothing to do, both ranges missing, only one missing,
# files absent entirely, range allocation past existing real users, and
# stale entries for deleted accounts (the Devuan live-installer leftover)
# not pushing the new range up.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-podman-subids-ensure"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-podman-subids-ensure ==="

# setup_mocks <existing-account> [<existing-account>...]: the getent stub
# says these accounts exist and nothing else does. The script under test
# runs as "testuser".
setup_mocks() {
  FAKE_ACCOUNTS=" $* "
  export FAKE_ACCOUNTS
  mock_bin id <<'EOF'
#!/bin/bash
echo testuser
EOF
  mock_bin getent <<'EOF'
#!/bin/bash
[[ "$FAKE_ACCOUNTS" == *" $2 "* ]]
EOF
  # sudo runs its argv for real so `sudo touch` and `sudo usermod` both
  # reach their stubs (touch is the real one, against scratch paths).
  mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "sudo $*"
exec "$@"
EOF
  mock_bin usermod <<'EOF'
#!/bin/bash
mock_log "usermod $*"
EOF
  mock_bin podman <<'EOF'
#!/bin/bash
mock_log "podman $*"
EOF
  SUBUID="$MOCK_DIR/subuid"
  SUBGID="$MOCK_DIR/subgid"
  sed -e "s#^SUBUID_FILE=.*#SUBUID_FILE=$SUBUID#" \
    -e "s#^SUBGID_FILE=.*#SUBGID_FILE=$SUBGID#" \
    -e "s#/usr/sbin/usermod#$MOCK_BIN/usermod#" \
    "$SCRIPT" >"$MOCK_DIR/subids-patched.sh"
}

run_ensure() {
  PATH="$(mock_path)" bash "$MOCK_DIR/subids-patched.sh" >"$MOCK_DIR/out.log" 2>&1
  echo $? >"$MOCK_DIR/rc"
}

# Scenario 1: both ranges already present -> exits 0 having called nothing.
mock_init
setup_mocks testuser
printf 'testuser:100000:65536\n' >"$SUBUID"
printf 'testuser:100000:65536\n' >"$SUBGID"
run_ensure
assert_eq "both present: exit 0" "0" "$(cat "$MOCK_DIR/rc")"
assert_eq "both present: nothing invoked" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# Scenario 2: files exist but have no entry for the user and no other
# entries either -> adds both ranges at the floor, then migrates podman.
mock_init
setup_mocks testuser
: >"$SUBUID"
: >"$SUBGID"
run_ensure
CALLS=$(cat "$MOCK_CALLS")
assert_eq "empty files: exit 0" "0" "$(cat "$MOCK_DIR/rc")"
assert_contains "empty files: usermod adds both ranges at 100000" "$CALLS" \
  "usermod --add-subuids 100000-165535 --add-subgids 100000-165535 testuser"
assert_contains "empty files: podman system migrate runs afterwards" "$CALLS" "podman system migrate"
assert_not_contains "empty files: no touch needed" "$CALLS" "sudo touch"
mock_cleanup

# Scenario 3: another real account already holds the first block -> the
# new range starts right after it, in both files.
mock_init
setup_mocks testuser alice
printf 'alice:100000:65536\n' >"$SUBUID"
printf 'alice:100000:65536\n' >"$SUBGID"
run_ensure
assert_contains "existing real user: next block allocated" "$(cat "$MOCK_CALLS")" \
  "usermod --add-subuids 165536-231071 --add-subgids 165536-231071 testuser"
mock_cleanup

# Scenario 4: the only existing entry belongs to an account that no longer
# exists (Devuan's live-installer "devuan" user copied into the installed
# system) -> ignored, the new user gets the floor block.
mock_init
setup_mocks testuser
printf 'devuan:100000:65536\n' >"$SUBUID"
printf 'devuan:100000:65536\n' >"$SUBGID"
run_ensure
assert_contains "stale entry for deleted account: skipped, floor block used" "$(cat "$MOCK_CALLS")" \
  "usermod --add-subuids 100000-165535 --add-subgids 100000-165535 testuser"
mock_cleanup

# Scenario 5: the two files disagree (a real user has a higher block in
# subgid only) -> the start is free in both, i.e. past the highest range
# across the pair, not just past the subuid ones.
mock_init
setup_mocks testuser alice bob
printf 'alice:100000:65536\n' >"$SUBUID"
printf 'alice:100000:65536\nbob:165536:65536\n' >"$SUBGID"
run_ensure
assert_contains "files disagree: start is past the highest range in either" "$(cat "$MOCK_CALLS")" \
  "usermod --add-subuids 231072-296607 --add-subgids 231072-296607 testuser"
mock_cleanup

# Scenario 6: only subgid is missing -> only --add-subgids is passed.
mock_init
setup_mocks testuser
printf 'testuser:100000:65536\n' >"$SUBUID"
: >"$SUBGID"
run_ensure
CALLS=$(cat "$MOCK_CALLS")
assert_contains "subgid only: --add-subgids passed" "$CALLS" "--add-subgids"
assert_not_contains "subgid only: --add-subuids not passed" "$CALLS" "--add-subuids"
mock_cleanup

# Scenario 7: neither file exists at all -> both get created (usermod
# refuses to write to a missing file) and both ranges added.
mock_init
setup_mocks testuser
run_ensure
CALLS=$(cat "$MOCK_CALLS")
assert_eq "no files: exit 0" "0" "$(cat "$MOCK_DIR/rc")"
assert_contains "no files: subuid created" "$CALLS" "sudo touch $SUBUID"
assert_contains "no files: subgid created" "$CALLS" "sudo touch $SUBGID"
assert_eq "no files: subuid exists afterwards" "yes" "$([[ -e "$SUBUID" ]] && echo yes)"
assert_contains "no files: both ranges added" "$CALLS" \
  "usermod --add-subuids 100000-165535 --add-subgids 100000-165535 testuser"
mock_cleanup

# Scenario 8: a malformed line (blank, or non-numeric fields) doesn't
# break allocation or get treated as a range.
mock_init
setup_mocks testuser alice
printf '\nalice:100000:65536\n# comment\nbroken:line\n' >"$SUBUID"
printf 'alice:100000:65536\n' >"$SUBGID"
run_ensure
assert_eq "malformed lines: exit 0" "0" "$(cat "$MOCK_DIR/rc")"
assert_contains "malformed lines: allocation unaffected" "$(cat "$MOCK_CALLS")" \
  "usermod --add-subuids 165536-231071 --add-subgids 165536-231071 testuser"
mock_cleanup

test_summary
