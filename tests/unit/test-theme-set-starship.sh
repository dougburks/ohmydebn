#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-starship: the Starship config is
# written once, and a config from before 4.12.0 gets the OhMyDebn logo in
# place of Starship's os module (which ran lsb_release before every prompt).
# Only a config that still has OhMyDebn's $os line is changed. Runs in a
# scratch HOME.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-starship"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-starship ==="

LOGO='[󰱰](bg:blue fg:black)\'

setup() {
  mock_init
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
echo "ohmydebn-headline $*" >>"$MOCK_CALLS"
EOF
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" \
    -e "s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" \
    "$SCRIPT" >"$MOCK_DIR/starship-patched.sh"
  H="$MOCK_DIR/home"
  STATE="$H/.local/state/ohmydebn-config"
  CONFIG="$H/.config/starship.toml"
  mkdir -p "$H/.config"
}
run() { HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/starship-patched.sh" >/dev/null 2>&1; STATUS=$?; }
# The config as OhMyDebn wrote it before 4.12.0: $os in the format, and its
# [os] tables before [username].
old_config() {
  sed "s/^\[󰱰\](bg:blue fg:black)\\\\\$/\$os\\\\/" "$REPO_ROOT/config/starship.toml" |
    awk '/^\[username\]$/ {
      print "[os]"; print "disabled = false"; print "style = \"bg:blue fg:black\""; print ""
      print "[os.symbols]"; print "Debian = \"󰣚\""; print "Ubuntu = \"󰕈\""; print ""
    } { print }'
}

# --- the shipped config has the logo and no os module ---
assert_eq "shipped config: the logo leads the prompt" "1" "$(grep -cxF "$LOGO" "$REPO_ROOT/config/starship.toml")"
assert_not_contains "shipped config: no os module" "$(cat "$REPO_ROOT/config/starship.toml")" '$os'
assert_not_contains "shipped config: no [os] table" "$(cat "$REPO_ROOT/config/starship.toml")" '[os'

# --- new install: the config is written, and the migration has nothing to do ---
setup
run
assert_eq "new install: succeeds" "0" "$STATUS"
assert_eq "new install: OhMyDebn's config written" "same" "$(cmp -s "$CONFIG" "$REPO_ROOT/config/starship.toml" && echo same)"
assert_not_contains "new install: no logo migration" "$(cat "$MOCK_CALLS")" "OhMyDebn logo"
assert_eq "new install: both markers written" "yes yes" \
  "$([ -f "$STATE/starship-20251109" ] && echo yes) $([ -f "$STATE/starship-logo-20261018" ] && echo yes)"
mock_cleanup

# --- a config from before 4.12.0: the logo replaces $os, the [os] tables go ---
setup
mkdir -p "$STATE"
touch "$STATE/starship-20251109"
old_config >"$CONFIG"
assert_eq "old config (test setup): has the \$os line" "1" "$(grep -cx '\$os\\' "$CONFIG")"
run
assert_eq "old config: succeeds" "0" "$STATUS"
assert_eq "old config: the logo replaces \$os" "1" "$(grep -cxF "$LOGO" "$CONFIG")"
assert_not_contains "old config: no os module left" "$(cat "$CONFIG")" '$os'
assert_not_contains "old config: its [os] tables are gone" "$(cat "$CONFIG")" '[os'
assert_contains "old config: the next table is kept" "$(cat "$CONFIG")" "[username]
show_always = true"
assert_eq "old config: now matches the shipped config, comments aside" "" \
  "$(diff <(grep -v '^#' "$CONFIG" | cat -s) <(grep -v '^#' "$REPO_ROOT/config/starship.toml" | cat -s))"
assert_contains "old config: says so" "$(cat "$MOCK_CALLS")" "Putting the OhMyDebn logo in the starship prompt"
# Once: a later \$os the user puts back stays.
old_config >"$CONFIG"
: >"$MOCK_CALLS"
run
assert_eq "again: a config changed after the migration is left alone" "1" "$(grep -cx '\$os\\' "$CONFIG")"
assert_eq "again: nothing said" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- a customised config (its own format) is never changed ---
setup
mkdir -p "$STATE"
touch "$STATE/starship-20251109"
printf 'format = "$os$directory$character"\n\n[os]\ndisabled = false\n' >"$CONFIG"
cp "$CONFIG" "$MOCK_DIR/before.toml"
run
assert_eq "customised config: unchanged" "same" "$(cmp -s "$CONFIG" "$MOCK_DIR/before.toml" && echo same)"
assert_eq "customised config: marker written all the same" "yes" "$([ -f "$STATE/starship-logo-20261018" ] && echo yes)"
mock_cleanup

# --- no config at all once the first one was written: nothing to do ---
setup
mkdir -p "$STATE"
touch "$STATE/starship-20251109"
run
assert_eq "config deleted: succeeds" "0" "$STATUS"
assert_eq "config deleted: not recreated" "no" "$([ -e "$CONFIG" ] && echo yes || echo no)"
mock_cleanup

test_summary
