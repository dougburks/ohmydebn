#!/bin/bash
#
# run.sh: Runs the whole ohmydebn test suite - lint (tier 1), mocked unit
# tests (tier 2), and read-only real-apt checks (tier 3) - and reports a
# single pass/fail summary. Nothing here touches the real system beyond
# read-only apt-cache/dpkg -l queries in apt-checks.sh.
#
# Usage: tests/run.sh [--skip-apt-checks]

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SKIP_APT_CHECKS=false
[[ "${1:-}" == "--skip-apt-checks" ]] && SKIP_APT_CHECKS=true

SUITES_RUN=0
SUITES_FAILED=0
FAILED_NAMES=()

run_suite() {
  local name="$1" script="$2"
  SUITES_RUN=$((SUITES_RUN + 1))
  echo
  echo "################################################################"
  echo "# $name"
  echo "################################################################"
  if ! bash "$script"; then
    SUITES_FAILED=$((SUITES_FAILED + 1))
    FAILED_NAMES+=("$name")
  fi
}

run_suite "lint" "tests/lint.sh"
run_suite "consistency" "tests/consistency.sh"

for t in tests/unit/*.sh; do
  run_suite "$(basename "$t" .sh)" "$t"
done

if [[ "$SKIP_APT_CHECKS" == false ]]; then
  run_suite "apt-checks" "tests/apt-checks.sh"
else
  echo
  echo "(skipping apt-checks per --skip-apt-checks)"
fi

echo
echo "################################################################"
echo "$((SUITES_RUN - SUITES_FAILED))/$SUITES_RUN suites passed"
if [[ $SUITES_FAILED -gt 0 ]]; then
  echo "failed: ${FAILED_NAMES[*]}"
fi
[[ $SUITES_FAILED -eq 0 ]]
