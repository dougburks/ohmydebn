#!/bin/bash
#
# Unit tests for bin/ohmydebn-tui-install. It gained ohmydebn-webapp-install's
# guards: no newline in the name or command (a desktop file takes the last
# of a duplicate key, so one could add a second Exec=), no leading '-' on
# the icon URL (curl would read it as an option), and curl -f so an error
# page isn't saved as the icon. The title is quoted so a " in the name
# can't end it early, and a literal % is %% (a lone % starts a field code).
# The written Exec line is parsed the way Cinnamon parses it. curl is a
# stand-in.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-tui-install"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-tui-install ==="

mock_init
mock_bin curl <<'STUB'
#!/bin/bash
echo "curl $*" >>"$MOCK_CALLS"
[[ "$*" == *404* ]] && exit 22
touch "$3"
STUB

install_tui() {
  : >"$MOCK_CALLS"
  rm -rf "${MOCK_DIR:?}/home"
  mkdir -p "$MOCK_DIR/home/.local/share/applications"
  HOME="$MOCK_DIR/home" PATH="$(mock_path)" bash "$SCRIPT" "$@" </dev/null >/dev/null 2>&1
}
launchers() { find "$MOCK_DIR/home/.local/share/applications" -name '*.desktop' | wc -l; }

install_tui $'Evil\nExec=touch /tmp/pwned' "htop" "https://example.com/icon.png"
assert_eq "refuses a newline in the name" "0" "$(launchers)"
install_tui "Evil" $'htop\nExec=touch /tmp/pwned' "https://example.com/icon.png"
assert_eq "refuses a newline in the command" "0" "$(launchers)"
install_tui "Good" "htop" "--config=/tmp/evil.conf"
assert_eq "refuses an icon URL starting with '-'" "" "$(cat "$MOCK_CALLS")"
install_tui "Good" "htop" "https://example.com/404.png"
assert_eq "an icon that can't be downloaded writes no launcher" "0" "$(launchers)"
assert_contains "the icon is fetched with curl -f, after --" "$(cat "$MOCK_CALLS")" "curl -fsSL -o"

NAME='My "Disk" 100%'
install_tui "$NAME" "bash -c 'dust; read -n 1 -s'" "https://example.com/icon.png"
ARGV=$(python3 "$REPO_ROOT/tests/lib/desktop-exec-argv.py" "$MOCK_DIR/home/.local/share/applications/$NAME.desktop" 2>&1)
assert_eq "the terminal gets the exact title and the command as typed" "/usr/share/ohmydebn/bin/ohmydebn-terminal
--class
TUI
--title
$NAME
-e
bash
-c
dust; read -n 1 -s" "$ARGV"

install_tui "Printf" 'printf "50%\n"' "https://example.com/icon.png"
ARGV=$(python3 "$REPO_ROOT/tests/lib/desktop-exec-argv.py" "$MOCK_DIR/home/.local/share/applications/Printf.desktop" 2>&1 | tail -2)
assert_eq "a % and a backslash in the command reach it unchanged" 'printf
50%\n' "$ARGV"

mock_cleanup
test_summary
