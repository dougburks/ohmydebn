#!/bin/bash
#
# Unit tests for bin/ohmydebn-webapp-remove and bin/ohmydebn-tui-remove
# given a name on the command line. They used to delete any
# ~/.local/share/applications/<name>.desktop, so
# `ohmydebn-webapp-remove firefox` removed a user's own firefox.desktop
# override. Now only a launcher the matching installer wrote is removed.
# HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== launcher removal only removes OhMyDebn's own launchers ==="

H=$(mktemp -d)
APPS="$H/.local/share/applications"
setup() {
  rm -rf "$APPS"
  mkdir -p "$APPS/icons"
  printf '[Desktop Entry]\nName=Firefox\nExec=firefox --private-window %%u\n' >"$APPS/firefox.desktop"
  printf '[Desktop Entry]\nName=Mail\nExec=/usr/share/ohmydebn/bin/ohmydebn-launch-webapp "https://mail.example.com"\n' >"$APPS/Mail.desktop"
  printf '[Desktop Entry]\nName=Top\nExec=/usr/share/ohmydebn/bin/ohmydebn-terminal --class TUI --title "Top" -e htop\n' >"$APPS/Top.desktop"
  : >"$APPS/icons/Mail.png"
  : >"$APPS/icons/Top.png"
}
exists() { [ -e "$APPS/$1" ] && echo yes || echo no; }

for remover in webapp tui; do
  setup
  HOME="$H" bash "$REPO_ROOT/bin/ohmydebn-$remover-remove" firefox </dev/null >/dev/null 2>&1
  assert_eq "$remover-remove firefox: the user's own firefox.desktop is kept" "yes" "$(exists firefox.desktop)"
done

setup
HOME="$H" bash "$REPO_ROOT/bin/ohmydebn-webapp-remove" Mail Top </dev/null >/dev/null 2>&1
assert_eq "webapp-remove: removes a web app" "no" "$(exists Mail.desktop)"
assert_eq "webapp-remove: and its icon" "no" "$(exists icons/Mail.png)"
assert_eq "webapp-remove: not a TUI launcher" "yes" "$(exists Top.desktop)"

setup
HOME="$H" bash "$REPO_ROOT/bin/ohmydebn-tui-remove" Top Mail </dev/null >/dev/null 2>&1
assert_eq "tui-remove: removes a TUI launcher" "no" "$(exists Top.desktop)"
assert_eq "tui-remove: not a web app" "yes" "$(exists Mail.desktop)"

rm -rf "$H"
test_summary
