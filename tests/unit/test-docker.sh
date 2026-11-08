#!/bin/bash
#
# Unit tests for bin/ohmydebn-docker-install and bin/ohmydebn-docker
# (Apps > Containers > Docker). Debian packages the docker command apart
# from the daemon, as docker-cli, which docker.io only recommends, so with
# recommends off (MX Linux) the installer gave the daemon alone. Ubuntu's
# docker.io has the command itself and there's no docker-cli package.
#
# dpkg answers from MOCK_INSTALLED, apt-cache knows docker-cli only when
# MOCK_HAS_CLI=1, and /usr/bin/docker is patched to a mock path that
# exists only when MOCK_HAS_COMMAND=1.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-docker-install, bin/ohmydebn-docker ==="

setup() {
  mock_init
  mock_bin dpkg <<'STUB'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
STUB
  mock_bin apt-cache <<'STUB'
#!/bin/bash
[[ "$1" == show && "$2" == docker-cli && "${MOCK_HAS_CLI:-}" == 1 ]] && exit 0
exit 100
STUB
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
STUB
  for name in ohmydebn-launch-floating-terminal ohmydebn-launch-floating-terminal-with-presentation; do
    mock_bin "$name" <<STUB
#!/bin/bash
mock_log "$name \$*"
STUB
  done
  mkdir -p "$MOCK_DIR/usr-bin"
  for script in ohmydebn-docker-install ohmydebn-docker; do
    sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/bin/docker#$MOCK_DIR/usr-bin/docker#g" \
      "$REPO_ROOT/bin/$script" >"$MOCK_DIR/$script"
  done
}

# run <script> <installed packages> <docker-cli exists: 0|1> <command present: 0|1> [args]
run() {
  local script="$1" installed="$2" has_cli="$3" has_command="$4"
  shift 4
  if [ "$has_command" = 1 ]; then
    printf '#!/bin/bash\n' >"$MOCK_DIR/usr-bin/docker"
    chmod +x "$MOCK_DIR/usr-bin/docker"
  else
    rm -f "$MOCK_DIR/usr-bin/docker"
  fi
  OUTPUT=$(MOCK_INSTALLED="$installed" MOCK_HAS_CLI="$has_cli" PATH="$(mock_path)" \
    bash "$MOCK_DIR/$script" "$@" </dev/null 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

# --- Debian: docker-cli is its own package, and is installed too ---
setup
run ohmydebn-docker-install "" 1 0 --skip-prompt
assert_eq "debian: exits 0" "0" "$STATUS"
assert_contains "debian: apt update first" "$CALLS" "sudo /usr/bin/apt update"
assert_contains "debian: installs docker.io and docker-cli" "$CALLS" "sudo /usr/bin/apt -y install docker.io docker-cli"
mock_cleanup

# --- Ubuntu: the command comes with docker.io, and there's no docker-cli ---
setup
run ohmydebn-docker-install "" 0 0 --skip-prompt
assert_eq "ubuntu: exits 0" "0" "$STATUS"
assert_contains "ubuntu: installs docker.io" "$CALLS" "sudo /usr/bin/apt -y install docker.io"
assert_not_contains "ubuntu: no docker-cli to ask for" "$CALLS" "docker-cli"
mock_cleanup

# --- installed with the command: nothing to do ---
setup
run ohmydebn-docker-install "docker.io docker-cli" 1 1 --skip-prompt
assert_contains "complete install: already installed" "$OUTPUT" "Docker is already installed."
assert_not_contains "complete install: installs nothing" "$CALLS" "apt"
mock_cleanup

# --- docker.io without docker-cli (recommends off): the installer finishes it ---
setup
run ohmydebn-docker-install "docker.io" 1 0 --skip-prompt
assert_not_contains "daemon only: not 'already installed'" "$OUTPUT" "already installed"
assert_contains "daemon only: installs docker-cli" "$CALLS" "sudo /usr/bin/apt -y install docker.io docker-cli"
mock_cleanup

setup
run ohmydebn-docker-install "docker.io" 1 0
assert_contains "daemon only, prompted: says what's missing" "$OUTPUT" "Docker is installed, but without its docker command."
assert_contains "daemon only, prompted: asks first" "$OUTPUT" "Press Enter"
mock_cleanup

# --- the launcher: opens Docker when it's complete ---
setup
run ohmydebn-docker "docker.io" 0 1
assert_not_contains "launcher, complete: no install" "$CALLS" "ohmydebn-launch-floating-terminal-with-presentation"
assert_contains "launcher, complete: opens Docker" "$CALLS" "ohmydebn-launch-floating-terminal Docker"
mock_cleanup

# --- the launcher: a daemon-only install opens the installer to finish it ---
setup
run ohmydebn-docker "docker.io" 1 0
assert_contains "launcher, daemon only: runs the installer" "$CALLS" "ohmydebn-launch-floating-terminal-with-presentation Docker"
assert_not_contains "launcher, daemon only (still missing): no docker --help" "$CALLS" "docker --help"
mock_cleanup

test_summary
