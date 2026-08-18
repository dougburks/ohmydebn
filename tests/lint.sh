#!/bin/bash
#
# lint.sh: Tier 1 - static checks. `bash -n` on every shell script (catches
# actual syntax errors) plus `shellcheck` where available (catches real bug
# classes we've hit before in this repo: unquoted glob expansion, SC2086,
# etc), and `python3 -m py_compile` on every Python script (ohmydebn-menu-
# picker/-theme-carousel/-theme-bg-carousel/-scale - none of these have a
# shebang the shell-script loop below would ever match, so without this
# second pass a syntax error in one of them would ship completely
# unnoticed by this suite). No infrastructure needed beyond the tools
# themselves - confirmed these scripts' module-level code runs fine with no
# real X display, so this needs no Xvfb either.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAIL=0
CHECKED=0

mapfile -d '' -t SCRIPTS < <(find bin install tests -type f -print0 | xargs -0 grep -lZ '^#!.*sh' 2>/dev/null)
mapfile -d '' -t PY_SCRIPTS < <(find bin install tests -type f -print0 | xargs -0 grep -lZ '^#!.*python' 2>/dev/null)

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

for f in "${PY_SCRIPTS[@]}"; do
  CHECKED=$((CHECKED + 1))
  if ! ERR=$(python3 -m py_compile "$f" 2>&1); then
    echo "FAIL (syntax): $f"
    echo "$ERR"
    FAIL=$((FAIL + 1))
  fi
done
rm -rf __pycache__ bin/__pycache__ install/__pycache__ tests/__pycache__

echo
echo "checked $CHECKED scripts, $FAIL failure(s)"
[[ $FAIL -eq 0 ]]
