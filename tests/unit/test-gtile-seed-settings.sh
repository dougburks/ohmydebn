#!/bin/bash
#
# Thin wrapper so tests/run.sh's `tests/unit/*.sh` discovery picks up
# test-gtile-seed-settings.py - the real test logic lives there in plain
# Python, not here (same reason test-theme-colors.sh exists).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$REPO_ROOT/tests/unit/test-gtile-seed-settings.py"
