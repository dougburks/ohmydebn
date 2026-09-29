#!/bin/bash
#
# Unit tests for bin/ohmydebn-socrates-run. SO-CRATES is published on
# 127.0.0.1 only: nothing else on the network needs it, and it shows the
# user's packet captures. Before 4.9.0 it was published on every interface
# and wrote pasta_options = ["-4"] into ~/.config/containers/containers.conf
# (so "localhost" over ::1 wouldn't hang), which turned off IPv6 in every
# rootless container the user runs. It must no longer write that file, and
# must leave a line from an older release alone.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-socrates-run"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-socrates-run ==="

setup_mocks() {
  mock_bin podman <<'EOF'
#!/bin/bash
echo "podman $*" >>"$MOCK_CALLS"
exit 0
EOF
  mock_bin ohmydebn-socrates-cleanup <<'EOF'
#!/bin/bash
echo "ohmydebn-socrates-cleanup $*" >>"$MOCK_CALLS"
exit 0
EOF
  mock_bin ohmydebn-podman-subids-ensure <<'EOF'
#!/bin/bash
echo "ohmydebn-podman-subids-ensure $*" >>"$MOCK_CALLS"
exit 0
EOF
  sed -e "s#/usr/bin/podman#$MOCK_BIN/podman#" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-socrates-cleanup#$MOCK_BIN/ohmydebn-socrates-cleanup#" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-podman-subids-ensure#$MOCK_BIN/ohmydebn-podman-subids-ensure#" \
    "$SCRIPT" >"$MOCK_DIR/socrates-run-patched.sh"
}

# Runs the patched script end-to-end (real podman/cleanup calls stubbed
# out, `read -r` at the end fed EOF via /dev/null so it returns instead of
# hanging).
run_socrates() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/socrates-run-patched.sh" </dev/null >/dev/null 2>&1
}

CONF_REL=".config/containers/containers.conf"

# Scenario 1: published on this computer only.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_socrates
assert_contains "port 8000 published on 127.0.0.1 only" "$(cat "$MOCK_CALLS")" "-p 127.0.0.1:8000:8000"
assert_not_contains "not published on every interface" "$(cat "$MOCK_CALLS")" "-p 8000:8000"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: no containers.conf -> none is created.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_socrates
assert_eq "no containers.conf is written" "no" "$([[ -e "$SCRATCH_HOME/$CONF_REL" ]] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: the -4 line an older release wrote -> left exactly as it is.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.config/containers"
printf '\n[network]\npasta_options = ["-4"]\n' >"$SCRATCH_HOME/$CONF_REL"
BEFORE=$(cat "$SCRATCH_HOME/$CONF_REL")
run_socrates
assert_eq "an existing containers.conf is left alone" "$BEFORE" "$(cat "$SCRATCH_HOME/$CONF_REL")"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 6: the subordinate-ID backfill runs, and runs before podman -
# it exists to fix the pull, so after would be useless.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_socrates
CALLS=$(cat "$MOCK_CALLS")
assert_contains "subids-ensure invoked" "$CALLS" "ohmydebn-podman-subids-ensure"
assert_eq "subids-ensure runs before podman" "ohmydebn-podman-subids-ensure" "$(head -n1 "$MOCK_CALLS" | cut -d' ' -f1)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
