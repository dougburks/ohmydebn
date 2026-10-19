#!/bin/bash
#
# Thin wrapper so tests/run.sh's `tests/unit/*.sh` discovery picks up
# test-panel-menu-launcher.py (same reason test-cinnamon-applet-ids.sh exists).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$REPO_ROOT/tests/unit/test-panel-menu-launcher.py"
