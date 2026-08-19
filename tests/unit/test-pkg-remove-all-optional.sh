#!/bin/bash
#
# Unit tests for bin/ohmydebn-pkg-remove-all-optional. Mocks dpkg/dpkg-l/
# sudo so nothing here touches the real system.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-pkg-remove-all-optional"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-pkg-remove-all-optional ==="

# Scenario 1 (regression test): a glob pattern matching HUNDREDS of "un"
# lines with the "ii" match early in the output used to falsely report as
# not-installed, because `dpkg -l ... | grep -q '^ii'` raced pipefail's
# SIGPIPE handling when grep exited before dpkg finished writing. This is
# the exact bug that caused "libreoffice*" to silently never get purged
# while "firefox*" (far fewer matching lines) worked fine.
mock_init
mock_bin dpkg <<'EOF'
#!/bin/bash
if [[ "$1" == "-l" && "$2" == "libreoffice*" ]]; then
  echo "ii  libreoffice-base-core  1.0  amd64  desc"
  for i in $(seq 1 500); do
    echo "un  libreoffice-grammarcheck-lang$i  <none>  <none>  desc"
  done
  exit 0
fi
exit 1
EOF
mock_bin sudo <<'EOF'
#!/bin/bash
echo "$*" >>"$MOCK_CALLS"
exit 0
EOF
PATH="$(mock_path)" bash "$SCRIPT" --skip-prompt </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "large glob match: still detected and purged despite SIGPIPE risk" "$CALLS" "purge libreoffice*"
mock_cleanup

# Scenario 2: multiple installed packages get purged in a single batched call
mock_init
mock_bin dpkg <<'EOF'
#!/bin/bash
if [[ "$1" == "-l" ]]; then
  case "$2" in
    brasero|"firefox*") echo "ii  $2  1.0  amd64  desc"; exit 0 ;;
    *) exit 1 ;;
  esac
fi
exit 1
EOF
mock_bin sudo <<'EOF'
#!/bin/bash
echo "$*" >>"$MOCK_CALLS"
exit 0
EOF
PATH="$(mock_path)" bash "$SCRIPT" --skip-prompt </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "batching: brasero and firefox* purged in one call" "$CALLS" "purge brasero firefox*"
mock_cleanup

# Scenario 3: default invocation shows the confirmation prompt; --skip-prompt doesn't
mock_init
mock_bin dpkg <<'EOF'
#!/bin/bash
exit 1
EOF
mock_bin sudo <<'EOF'
#!/bin/bash
exit 0
EOF
DEFAULT_OUTPUT=$(PATH="$(mock_path)" bash "$SCRIPT" </dev/null 2>&1)
SKIP_OUTPUT=$(PATH="$(mock_path)" bash "$SCRIPT" --skip-prompt </dev/null 2>&1)
assert_contains "default: shows confirmation prompt" "$DEFAULT_OUTPUT" "Press Enter to continue"
assert_not_contains "--skip-prompt: does not show confirmation prompt" "$SKIP_OUTPUT" "Press Enter to continue"
mock_cleanup

# Scenario 4: batch purge fails -> falls back to purging one at a time
mock_init
mock_bin dpkg <<'EOF'
#!/bin/bash
if [[ "$1" == "-l" ]]; then
  case "$2" in
    brasero|"firefox*") echo "ii  $2  1.0  amd64  desc"; exit 0 ;;
    *) exit 1 ;;
  esac
fi
exit 1
EOF
mock_bin sudo <<'EOF'
#!/bin/bash
echo "$*" >>"$MOCK_CALLS"
if [[ "$1" == "/usr/bin/apt" && "$3" == "purge" ]]; then
  shift 3
  if [[ "$#" -gt 1 ]]; then
    exit 100
  fi
fi
exit 0
EOF
PATH="$(mock_path)" bash "$SCRIPT" --skip-prompt </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "purge batch failure: attempted as one batch first" "$CALLS" "purge brasero firefox*"
assert_contains "purge batch failure: falls back to brasero alone" "$CALLS" "purge brasero
"
mock_cleanup

test_summary
