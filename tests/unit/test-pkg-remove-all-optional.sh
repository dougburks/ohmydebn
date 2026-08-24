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

# Scenario 5: the dedicated-remove-script dispatch (both the shared
# PACKAGE loop and Pi's own special case right after it - Pi can't join
# that loop because its dpkg package name, ohmydebn-pi-coding-agent,
# isn't the same string as its remove script's ohmydebn-pi-remove, unlike
# every other entry there). Patches /usr/share/ohmydebn/bin -> $MOCK_BIN
# (same technique test-power-user-flow.sh uses) so the mocked remove
# scripts are what actually get invoked.
mock_init
mock_bin dpkg <<'EOF'
#!/bin/bash
# -l (the batch-glob-purge list) reports nothing installed, so that part
# of the script contributes nothing to $MOCK_CALLS and this scenario
# stays isolated to the dedicated-remove-script dispatch below it.
[[ "$1" == "-l" ]] && exit 1
if [[ "$1" == "-s" ]]; then
  case "$2" in
  claude-code | ohmydebn-pi-coding-agent) exit 0 ;;
  *) exit 1 ;;
  esac
fi
exit 1
EOF
mock_bin sudo <<'EOF'
#!/bin/bash
echo "sudo $*" >>"$MOCK_CALLS"
exit 0
EOF
mock_bin ohmydebn-claude-code-remove <<'EOF'
#!/bin/bash
echo "ohmydebn-claude-code-remove $*" >>"$MOCK_CALLS"
EOF
mock_bin ohmydebn-pi-remove <<'EOF'
#!/bin/bash
echo "ohmydebn-pi-remove $*" >>"$MOCK_CALLS"
EOF
sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/pkg-remove-all-optional-patched.sh"
PATH="$(mock_path)" bash "$MOCK_DIR/pkg-remove-all-optional-patched.sh" --skip-prompt </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "dedicated-remove loop: installed claude-code gets removed" "$CALLS" "ohmydebn-claude-code-remove --skip-prompt"
assert_contains "Pi special case: installed Pi gets removed" "$CALLS" "ohmydebn-pi-remove --skip-prompt"
assert_not_contains "dedicated-remove loop: not-installed chatgpt is left alone" "$CALLS" "ohmydebn-chatgpt-remove"
mock_cleanup

# Scenario 6: on Kali, Firefox is Kali's default and only preinstalled
# browser (unlike the Debian Cinnamon ISO, which also ships other apps
# this script removes), so it must be left alone even though it's
# installed and would otherwise match the "firefox*" glob.
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
echo "ID=kali" >"$MOCK_DIR/os-release"
OHMYDEBN_TEST_OS_RELEASE="$MOCK_DIR/os-release" PATH="$(mock_path)" bash "$SCRIPT" --skip-prompt </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "Kali: brasero still purged" "$CALLS" "purge brasero"
assert_not_contains "Kali: firefox* left alone" "$CALLS" "firefox*"
mock_cleanup

test_summary
