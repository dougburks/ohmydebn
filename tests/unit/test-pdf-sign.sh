#!/bin/bash
#
# Runs test-pdf-sign.py. A thin wrapper so tests/run.sh, which runs every
# tests/unit/*.sh, picks it up.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/test-pdf-sign.py"
