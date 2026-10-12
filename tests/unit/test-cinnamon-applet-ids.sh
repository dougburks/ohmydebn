#!/bin/bash
#
# Thin wrapper so tests/run.sh's `tests/unit/*.sh` discovery picks up
# test-cinnamon-applet-ids.py (same reason test-update-gui.sh exists).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$REPO_ROOT/tests/unit/test-cinnamon-applet-ids.py"
