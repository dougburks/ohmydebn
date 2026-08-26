#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-remove's guard against a theme name that
# escapes THEMES_DIR on its way into `rm -rf`. The name here comes straight
# from a CLI argument (not derived from a URL, so there's no git
# transport-helper class of bug to cover - see test-theme-install-guards.sh
# and test-theme-install-all-guards.sh for that), but a name like ".." or
# "../etc" would otherwise point THEME_PATH at an ancestor of THEMES_DIR.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-remove"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-remove ==="

setup_mocks() {
  mock_bin rm <<'EOF'
#!/bin/bash
echo "rm $*" >>"$MOCK_CALLS"
exit 0
EOF
}

remove_theme() {
  : >"$MOCK_CALLS"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$SCRIPT" "$1" >/dev/null 2>&1
}

fresh_scratch_home() {
  [[ -n "${SCRATCH_HOME:-}" ]] && rm -rf "$SCRATCH_HOME"
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/themes"
}

mock_init
setup_mocks

# --- A name that could escape THEMES_DIR must never reach rm ---
for name in ".." "." ".git" "../etc" "a/b" "/etc/passwd" ""; do
  fresh_scratch_home
  if remove_theme "$name"; then
    assert_eq "refuses escaping name '$name'" "rejected" "accepted"
  else
    assert_eq "refuses escaping name '$name'" "rejected" "rejected"
  fi
  assert_eq "'$name' never reaches rm" "" "$(cat "$MOCK_CALLS")"
done

# --- A well-formed name for a theme that isn't installed is refused before rm ---
fresh_scratch_home
if remove_theme "not-installed"; then
  assert_eq "refuses a theme that was never installed" "rejected" "accepted"
else
  assert_eq "refuses a theme that was never installed" "rejected" "rejected"
fi
assert_eq "missing theme never reaches rm" "" "$(cat "$MOCK_CALLS")"

# --- The ordinary case still works ---
fresh_scratch_home
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/themes/cool"
remove_theme "cool"
assert_contains "removes an installed theme" "$(cat "$MOCK_CALLS")" "themes/cool"

rm -rf "$SCRATCH_HOME"
mock_cleanup
test_summary
