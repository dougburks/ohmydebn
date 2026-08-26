#!/bin/bash
#
# Runs test-aether-url-guard.py. A thin wrapper so `bash
# test-aether-url-guard.sh` still works the same way it always has here.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/test-aether-url-guard.py"
