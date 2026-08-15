#!/bin/bash
#
# lint.sh: Tier 1 - static checks. `bash -n` on every script (catches
# actual syntax errors) plus `shellcheck` where available (catches real bug
# classes we've hit before in this repo: unquoted glob expansion, SC2086,
# etc). No infrastructure needed beyond the tools themselves.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAIL=0
CHECKED=0

mapfile -d '' -t SCRIPTS < <(find bin install tests -type f -print0 | xargs -0 grep -lZ '^#!.*sh' 2>/dev/null)

if command -v shellcheck >/dev/null 2>&1; then
  HAVE_SHELLCHECK=true
else
  echo "shellcheck not installed - skipping shellcheck pass, bash -n only" >&2
  HAVE_SHELLCHECK=false
fi

for f in "${SCRIPTS[@]}"; do
  CHECKED=$((CHECKED + 1))
  if ! ERR=$(bash -n "$f" 2>&1); then
    echo "FAIL (syntax): $f"
    echo "$ERR"
    FAIL=$((FAIL + 1))
  fi

  if [[ "$HAVE_SHELLCHECK" == true ]]; then
    # -S warning: only fail on real bugs, not every style nit, so this
    # stays useful signal rather than noise to ignore.
    if ! ERR=$(shellcheck -S warning -e SC1091 "$f" 2>&1); then
      echo "FAIL (shellcheck): $f"
      echo "$ERR"
      FAIL=$((FAIL + 1))
    fi
  fi
done

echo
echo "checked $CHECKED scripts, $FAIL failure(s)"
[[ $FAIL -eq 0 ]]
