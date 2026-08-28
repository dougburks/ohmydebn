#!/bin/bash
#
# Thin wrapper so tests/run.sh's `tests/unit/*.sh` discovery picks up
# test-virtmanager-passt-upgrade.py - the real test logic lives there in
# plain Python, same convention as test-python-pickers.sh.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$REPO_ROOT/tests/unit/test-virtmanager-passt-upgrade.py"
