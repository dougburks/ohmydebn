#!/bin/bash
#
# Thin wrapper so tests/run.sh's `tests/unit/*.sh` discovery picks up
# test-speedtest-common.py - the real test logic lives there in plain
# Python, not here (same reason test-python-pickers.sh exists).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$REPO_ROOT/tests/unit/test-speedtest-common.py"
