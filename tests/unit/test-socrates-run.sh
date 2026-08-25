#!/bin/bash
#
# Unit tests for bin/ohmydebn-socrates-run's ensure_pasta_ipv4() guard.
# Rootless podman's pasta network backend forwards published ports on both
# IPv4 and IPv6; on systems where "localhost" resolves to ::1 before
# 127.0.0.1 (the default on most current Debian-family systems, Kali
# included), the browser connects over IPv6 while the so-crates container
# only listens on IPv4, so port 8000 looks unreachable. ensure_pasta_ipv4()
# forces pasta to IPv4-only via ~/.config/containers/containers.conf -
# these tests cover the four shapes that file can already be in: missing,
# present with a [network] section but no pasta_options, present with
# pasta_options already set (must not be clobbered), and present with no
# [network] section at all.

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
  sed -e "s#/usr/bin/podman#$MOCK_BIN/podman#" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-socrates-cleanup#$MOCK_BIN/ohmydebn-socrates-cleanup#" \
    "$SCRIPT" >"$MOCK_DIR/socrates-run-patched.sh"
}

# Runs the patched script end-to-end (real podman/cleanup calls stubbed
# out, `read -r` at the end fed EOF via /dev/null so it returns instead of
# hanging) so this exercises ensure_pasta_ipv4() exactly as socrates-run
# actually calls it, not in isolation.
run_socrates() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/socrates-run-patched.sh" </dev/null >/dev/null 2>&1
}

CONF_REL=".config/containers/containers.conf"

# Scenario 1: no containers.conf at all -> one gets created with a
# [network] section forcing pasta to IPv4-only.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_socrates
CONF="$SCRATCH_HOME/$CONF_REL"
assert_contains "no conf: creates one with pasta_options" "$(cat "$CONF" 2>/dev/null)" 'pasta_options = ["-4"]'
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: [network] section exists but no pasta_options -> the key is
# inserted into that section, everything else in the file is preserved.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.config/containers"
CONF="$SCRATCH_HOME/$CONF_REL"
cat >"$CONF" <<'EOF'
[containers]
log_size_max = 10000

[network]
default_network = "podman"

[engine]
EOF
run_socrates
RESULT=$(cat "$CONF")
assert_contains "existing [network], no key: pasta_options added" "$RESULT" 'pasta_options = ["-4"]'
assert_contains "existing [network], no key: default_network preserved" "$RESULT" 'default_network = "podman"'
assert_contains "existing [network], no key: unrelated [containers] section preserved" "$RESULT" "log_size_max = 10000"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: pasta_options already set to something else -> left alone,
# not overwritten with -4.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.config/containers"
CONF="$SCRATCH_HOME/$CONF_REL"
cat >"$CONF" <<'EOF'
[network]
pasta_options = ["-t", "auto"]
EOF
run_socrates
assert_eq "existing pasta_options: untouched" '[network]
pasta_options = ["-t", "auto"]' "$(cat "$CONF")"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 4: containers.conf exists but has no [network] section at all
# -> a new [network] section is appended, existing content preserved.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.config/containers"
CONF="$SCRATCH_HOME/$CONF_REL"
cat >"$CONF" <<'EOF'
[engine]
runtime = "crun"
EOF
run_socrates
RESULT=$(cat "$CONF")
assert_contains "no [network] section: one is appended with pasta_options" "$RESULT" 'pasta_options = ["-4"]'
assert_contains "no [network] section: existing [engine] section preserved" "$RESULT" 'runtime = "crun"'
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 5: podman still gets invoked with the expected image/port args
# (ensure_pasta_ipv4 runs before it, doesn't short-circuit the rest of the
# script).
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_socrates
assert_contains "podman still invoked after the containers.conf guard" "$(cat "$MOCK_CALLS")" "-p 8000:8000"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
