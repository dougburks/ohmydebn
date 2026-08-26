#!/bin/bash
#
# Unit tests for bin/ohmydebn-pkg-install-optional. Mocks dpkg-query/dpkg/
# apt-cache/sudo so nothing here touches the real system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-pkg-install-optional"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

# Sets up dpkg-query/dpkg/apt-cache/sudo stubs driven by two flat files in
# $MOCK_DIR: installed.txt (one package per line = currently installed) and
# unavailable.txt (one package per line = apt-cache show fails for it).
# sudo logs every call to $MOCK_CALLS and, for an apt install, appends the
# installed packages to installed.txt unless $MOCK_DIR/batch-fail exists
# (which makes exactly one batch install call fail, to exercise the
# fallback path).
setup_common_mocks() {
  : >"$MOCK_DIR/installed.txt"
  : >"$MOCK_DIR/unavailable.txt"

  mock_bin dpkg-query <<'EOF'
#!/bin/bash
EXIT=0
for p in "$@"; do
  [[ "$p" == "-W" || "$p" == -f=* ]] && continue
  if grep -qxF "$p" "$MOCK_DIR/installed.txt" 2>/dev/null; then
    echo "$p install ok installed"
  else
    echo "$p unknown ok not-installed"
    EXIT=1
  fi
done
exit $EXIT
EOF

  mock_bin dpkg <<'EOF'
#!/bin/bash
[[ "$1" == "-s" ]] && grep -qxF "$2" "$MOCK_DIR/installed.txt" 2>/dev/null && exit 0
exit 1
EOF

  mock_bin apt-cache <<'EOF'
#!/bin/bash
[[ "$1" == "show" ]] && grep -qxF "$2" "$MOCK_DIR/unavailable.txt" 2>/dev/null && exit 100
exit 0
EOF

  mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "sudo $*"
if [[ "$1" == "/usr/bin/apt" ]]; then
  # Find "install" among the args (position varies with --no-install-recommends)
  args=("$@")
  for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == "install" ]]; then
      pkgs=("${args[@]:$((i+1))}")
      if [[ "${#pkgs[@]}" -gt 1 && -f "$MOCK_DIR/batch-fail" ]]; then
        rm -f "$MOCK_DIR/batch-fail"
        exit 100
      fi
      for p in "${pkgs[@]}"; do echo "$p" >>"$MOCK_DIR/installed.txt"; done
      exit 0
    fi
  done
  exit 0
fi
[[ "$1" == "/usr/bin/apt-mark" ]] && exit 0
exit 0
EOF
}

echo "=== ohmydebn-pkg-install-optional ==="

# Scenario 1: already-installed package -> no apt install, still apt-mark manual
mock_init
setup_common_mocks
echo "bash" >"$MOCK_DIR/installed.txt"
PATH="$(mock_path)" bash "$SCRIPT" bash >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "already-installed: no apt install call" "$CALLS" "install bash"
assert_contains "already-installed: still apt-mark manual" "$CALLS" "apt-mark manual bash"
mock_cleanup

# Scenario 2: not-installed + available -> batched install + apt-mark manual
mock_init
setup_common_mocks
PATH="$(mock_path)" bash "$SCRIPT" htop ripgrep >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "batch install: single call installs both packages" "$CALLS" "install htop ripgrep"
assert_contains "batch install: both marked manual afterward" "$CALLS" "apt-mark manual htop ripgrep"
mock_cleanup

# Scenario 3: unavailable package is filtered out before ever reaching apt
mock_init
setup_common_mocks
echo "definitely-not-a-real-package-xyz" >"$MOCK_DIR/unavailable.txt"
OUTPUT=$(PATH="$(mock_path)" bash "$SCRIPT" definitely-not-a-real-package-xyz htop 2>&1)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "unavailable: warns and skips" "$OUTPUT" "not available on this system"
assert_not_contains "unavailable: never passed to apt install" "$CALLS" "definitely-not-a-real-package-xyz"
assert_contains "unavailable: available package still installs" "$CALLS" "install htop"
mock_cleanup

# Scenario 4: batch install fails -> falls back to installing one at a time
mock_init
setup_common_mocks
touch "$MOCK_DIR/batch-fail"
PATH="$(mock_path)" bash "$SCRIPT" htop ripgrep fzf >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "batch failure: attempted as one batch first" "$CALLS" "install htop ripgrep fzf"
assert_contains "batch failure: falls back to htop alone" "$CALLS" "install htop
"
assert_contains "batch failure: falls back to ripgrep alone" "$CALLS" "install ripgrep
"
assert_contains "batch failure: falls back to fzf alone" "$CALLS" "install fzf
"
mock_cleanup

# Scenario 5: package name with a literal dot is matched by exact string
# comparison, not treated as a regex wildcard (regression test)
mock_init
setup_common_mocks
echo "libglib2.0-bin" >"$MOCK_DIR/installed.txt"
PATH="$(mock_path)" bash "$SCRIPT" libglib2.0-bin >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "dotted name: already-installed, no install call" "$CALLS" "install libglib2.0-bin"
assert_contains "dotted name: correctly marked manual" "$CALLS" "apt-mark manual libglib2.0-bin"
mock_cleanup

test_summary
