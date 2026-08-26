#!/bin/bash
#
# test-helpers.sh: Shared mocking + assertion helpers for ohmydebn's test
# suite. Source this from a test file. The mocking approach here (a scratch
# PATH directory full of fake dpkg/apt/sudo stubs, run the real script
# against it, assert on what got called) is the same technique used
# throughout development to verify fixes without touching the real system -
# these files just make that pattern reusable instead of ad hoc.
#
# Usage in a test file:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-helpers.sh"
#   mock_init
#   mock_bin dpkg <<'EOF'
#   #!/bin/bash
#   exit 1
#   EOF
#   OUTPUT=$(PATH="$(mock_path)" bash /path/to/script-under-test 2>&1)
#   assert_contains "does the thing" "$OUTPUT" "expected substring"
#   mock_cleanup
#   test_summary

TESTS_RUN=0
TESTS_FAILED=0

# Create a fresh scratch dir with an empty bin/ for stubs and a call log.
# Exports MOCK_DIR/MOCK_BIN/MOCK_CALLS so stub scripts (run as subprocesses)
# can see them too.
mock_init() {
  MOCK_DIR=$(mktemp -d)
  MOCK_BIN="$MOCK_DIR/bin"
  MOCK_CALLS="$MOCK_DIR/calls.log"
  mkdir -p "$MOCK_BIN"
  : >"$MOCK_CALLS"
  export MOCK_DIR MOCK_BIN MOCK_CALLS
  # Stubs run as their own bash process (not sourced), so without this,
  # `mock_log` called from inside a stub is just a missing command - export
  # -f is what makes the "call mock_log from inside a stub" usage below
  # actually work there instead of silently doing nothing.
  export -f mock_log
}

mock_cleanup() {
  [[ -n "${MOCK_DIR:-}" ]] && rm -rf "$MOCK_DIR"
}

# mock_bin <command-name>: writes stdin (a full script, shebang included)
# to $MOCK_BIN/<command-name> and makes it executable. Use `mock_log "$*"`
# inside the stub body to record invocations to $MOCK_CALLS.
mock_bin() {
  local name="$1"
  cat >"$MOCK_BIN/$name"
  chmod +x "$MOCK_BIN/$name"
}

# Call from inside a stub script to record its invocation.
mock_log() {
  echo "$*" >>"$MOCK_CALLS"
}

# Returns a PATH string with the mock bin directory first.
mock_path() {
  echo "$MOCK_BIN:$PATH"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  ok - $desc"
  else
    echo "  FAIL - $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ok - $desc"
  else
    echo "  FAIL - $desc"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ok - $desc"
  else
    echo "  FAIL - $desc"
    echo "    expected NOT to contain: $needle"
    echo "    actual: $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Prints a summary and returns non-zero if any assertion failed - use as
# the last line of a test file so its own exit code reflects the result.
test_summary() {
  echo
  echo "$((TESTS_RUN - TESTS_FAILED))/$TESTS_RUN passed"
  [[ $TESTS_FAILED -eq 0 ]]
}
