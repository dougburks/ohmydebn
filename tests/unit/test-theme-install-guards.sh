#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-install's guards against git argument/
# transport-helper injection and theme-name path escape. ohmydebn-theme-install
# feeds a pasted URL to `git clone` and a name derived from it to `rm -rf`, so
# both are exercised here with git and ohmydebn-theme-set stubbed out - a
# guard that stopped working shows up as a clone or removal that should never
# have been reached.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-install"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-install ==="

setup_mocks() {
  mock_bin git <<'EOF'
#!/bin/bash
echo "git $*" >>"$MOCK_CALLS"
if [[ "$1" == "clone" ]]; then
  mkdir -p "${*: -1}"
fi
exit 0
EOF
  mock_bin ohmydebn-theme-set <<'EOF'
#!/bin/bash
echo "ohmydebn-theme-set $*" >>"$MOCK_CALLS"
exit 0
EOF
  sed "s#/usr/share/ohmydebn/bin/ohmydebn-theme-set#$MOCK_BIN/ohmydebn-theme-set#g" "$SCRIPT" >"$MOCK_DIR/theme-install-patched.sh"
}

install_theme() {
  : >"$MOCK_CALLS"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/theme-install-patched.sh" "$1" >/dev/null 2>&1
}

fresh_scratch_home() {
  [[ -n "${SCRATCH_HOME:-}" ]] && rm -rf "$SCRATCH_HOME"
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/themes"
}

mock_init
setup_mocks

# --- A URL git would read as an option or as a remote transport helper to run ---
for url in "-x" "--upload-pack=touch /tmp/pwned" "ext::sh -c id" "fd::0,1"; do
  fresh_scratch_home
  if install_theme "$url"; then
    assert_eq "refuses git-option/transport-helper URL '$url'" "rejected" "accepted"
  else
    assert_eq "refuses git-option/transport-helper URL '$url'" "rejected" "rejected"
  fi
  assert_eq "'$url' never reaches git" "" "$(cat "$MOCK_CALLS")"
done

# --- A URL whose derived name would escape the themes directory ---
for url in "https://example.com/..git" "https://example.com/.git"; do
  fresh_scratch_home
  if install_theme "$url"; then
    assert_eq "refuses escaping derived name from '$url'" "rejected" "accepted"
  else
    assert_eq "refuses escaping derived name from '$url'" "rejected" "rejected"
  fi
  assert_eq "'$url' never reaches git" "" "$(cat "$MOCK_CALLS")"
done

# --- basename reads a leading dash as an option once the scp-style prefix is gone ---
fresh_scratch_home
install_theme "host:-s/foo.git"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "passes the URL after --" "$CALLS" "-- host:-s/foo.git"
assert_contains "derives 'foo', not '.git'" "$CALLS" "/themes/foo"

# --- The ordinary case still works ---
fresh_scratch_home
install_theme "https://github.com/example/omarchy-cool-theme.git"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "clones a normal URL" "$CALLS" "/themes/cool"
assert_contains "applies the theme it installed" "$CALLS" "ohmydebn-theme-set cool"

rm -rf "$SCRATCH_HOME"
mock_cleanup
test_summary
