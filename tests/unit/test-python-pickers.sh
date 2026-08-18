#!/bin/bash
#
# Thin wrapper so tests/run.sh's `tests/unit/*.sh` discovery picks up
# test-python-pickers.py - the real test logic lives there in plain Python
# (native tuples/lists/dicts beat round-tripping through captured stdout
# for the data these functions return), not here.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$REPO_ROOT/tests/unit/test-python-pickers.py"
