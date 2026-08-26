#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-install-all's guards against git
# argument/transport-helper injection and theme-name path escape - the same
# class of bug ohmydebn-theme-install guards against (see
# test-theme-install-guards.sh), but here the URL comes from scraping a
# remote page with `grep github.com | cut -d\" -f2` instead of from a pasted
# argument, so a crafted page entry that merely contains the substring
# "github.com" somewhere is enough to reach the extracted field.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-install-all"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-install-all ==="

setup_mocks() {
  mock_bin git <<'EOF'
#!/bin/bash
echo "git $*" >>"$MOCK_CALLS"
if [[ "$1" == "clone" ]]; then
  mkdir -p "${*: -1}"
fi
exit 0
EOF
}

# $1: the raw line curl should emit for the page fetch (already containing
# the substring "github.com" so the script's own grep passes it through).
install_all() {
  : >"$MOCK_CALLS"
  mock_bin curl <<EOF
#!/bin/bash
echo '$1'
EOF
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$SCRIPT" </dev/null >/dev/null 2>&1
}

fresh_scratch_home() {
  [[ -n "${SCRATCH_HOME:-}" ]] && rm -rf "$SCRATCH_HOME"
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/themes"
}

mock_init
setup_mocks

# --- A scraped field git would read as an option or as a remote transport
# helper to run, smuggled past the page's own "github.com" substring filter ---
for payload in '-x' '--upload-pack=touch /tmp/pwned' 'ext::sh -c id' 'fd::0,1'; do
  fresh_scratch_home
  install_all "<a href=\"$payload\">github.com</a>"
  assert_eq "'$payload' never reaches git" "" "$(cat "$MOCK_CALLS")"
done

# --- A scraped field whose derived name would escape the themes directory ---
for payload in "https://example.com/..git" "https://example.com/.git"; do
  fresh_scratch_home
  install_all "<a href=\"$payload\">github.com</a>"
  assert_eq "escaping derived name from '$payload' never reaches git" "" "$(cat "$MOCK_CALLS")"
done

# --- The ordinary case still works ---
fresh_scratch_home
install_all '<a href="https://github.com/example/omarchy-cool-theme.git">link</a>'
CALLS=$(cat "$MOCK_CALLS")
assert_contains "clones a normal URL" "$CALLS" "/themes/cool"
assert_contains "clone uses -- separator" "$CALLS" "-- https://github.com/example/omarchy-cool-theme.git"

rm -rf "$SCRATCH_HOME"
mock_cleanup
test_summary
