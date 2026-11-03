#!/bin/bash
#
# Unit tests for bin/ohmydebn-herdr-config: turns off herdr's own version
# check once per user (OhMyDebn updates herdr through apt), never
# replacing a version_check the user set, and keeping the rest of their
# config. dpkg is mocked; HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-herdr-config: herdr's update check off, once ==="

# setup <yes|no: herdr installed>
setup() {
  mock_init
  if [ "$1" = yes ]; then
    mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "herdr" ]] && exit 0
exit 1
EOF2
  else
    mock_bin dpkg <<'EOF2'
#!/bin/bash
exit 1
EOF2
  fi
  SCRATCH_HOME=$(mktemp -d)
  CONFIG="$SCRATCH_HOME/.config/herdr/config.toml"
  STATE="$SCRATCH_HOME/.local/state/ohmydebn-config/herdr-version-check-off"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

run_config() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$REPO_ROOT/bin/ohmydebn-herdr-config"
}

# version_check <file>: herdr's [update] version_check as TOML reads it.
version_check() {
  python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb")).get("update", {}).get("version_check", "unset"))' "$1"
}

# --- herdr not installed: nothing written, no marker (so a later install still gets it) ---
setup no
run_config
assert_eq "not installed: no config written" "no" "$([ -e "$CONFIG" ] && echo yes || echo no)"
assert_eq "not installed: no marker" "no" "$([ -e "$STATE" ] && echo yes || echo no)"
teardown

# --- no config yet: one is made with just the setting ---
setup yes
run_config
assert_eq "no config: version_check is off" "False" "$(version_check "$CONFIG")"
assert_eq "no config: marker set" "yes" "$([ -f "$STATE" ] && echo yes || echo no)"
teardown

# --- an existing [update] table gets the line (TOML allows the table only once) ---
setup yes
mkdir -p "$(dirname "$CONFIG")"
printf '[keys]\nprefix = "ctrl+a"\n\n[update] # mine\nchannel = "stable"\n\n[ui]\naccent = "blue"\n' >"$CONFIG"
run_config
assert_eq "[update] present: version_check is off" "False" "$(version_check "$CONFIG")"
assert_eq "[update] present: one [update] table" "1" "$(grep -c '^\[update\]' "$CONFIG")"
assert_eq "[update] present: the user's other settings kept" "ctrl+a stable blue" \
  "$(python3 -c 'import sys, tomllib; c = tomllib.load(open(sys.argv[1], "rb")); print(c["keys"]["prefix"], c["update"]["channel"], c["ui"]["accent"])' "$CONFIG")"
teardown

# --- a config without [update] gets the table appended ---
setup yes
mkdir -p "$(dirname "$CONFIG")"
printf '[keys]\nprefix = "ctrl+a"\n' >"$CONFIG"
run_config
assert_eq "no [update]: version_check is off" "False" "$(version_check "$CONFIG")"
assert_contains "no [update]: the user's settings kept" "$(cat "$CONFIG")" 'prefix = "ctrl+a"'
teardown

# --- herdr's commented default template: the commented line doesn't count as the user's ---
setup yes
mkdir -p "$(dirname "$CONFIG")"
printf '[update]\n# Check herdr.dev for new Herdr versions in the background.\n# version_check = true\n' >"$CONFIG"
run_config
assert_eq "commented default: version_check is off" "False" "$(version_check "$CONFIG")"
teardown

# --- a version_check the user set is left alone ---
setup yes
mkdir -p "$(dirname "$CONFIG")"
printf '[update]\nversion_check = true\n' >"$CONFIG"
BEFORE=$(cat "$CONFIG")
run_config
assert_eq "user's own setting: config unchanged" "$BEFORE" "$(cat "$CONFIG")"
assert_eq "user's own setting: marker set" "yes" "$([ -f "$STATE" ] && echo yes || echo no)"
teardown

# --- once only: a user who later deletes the line keeps the check on ---
setup yes
run_config
printf '[update]\n' >"$CONFIG"
run_config
assert_eq "second run after the user removed it: not re-added" "unset" "$(version_check "$CONFIG")"
teardown

# --- XDG_CONFIG_HOME is where herdr looks when it's set ---
setup yes
HOME="$SCRATCH_HOME" XDG_CONFIG_HOME="$SCRATCH_HOME/xdg" PATH="$(mock_path)" bash "$REPO_ROOT/bin/ohmydebn-herdr-config"
assert_eq "XDG_CONFIG_HOME: written there" "False" "$(version_check "$SCRATCH_HOME/xdg/herdr/config.toml")"
teardown

# --- a symlinked config stays a link ---
setup yes
mkdir -p "$(dirname "$CONFIG")" "$SCRATCH_HOME/dotfiles"
printf '[update]\nchannel = "stable"\n' >"$SCRATCH_HOME/dotfiles/herdr.toml"
ln -s "$SCRATCH_HOME/dotfiles/herdr.toml" "$CONFIG"
run_config
assert_eq "symlinked config: still a link" "yes" "$([ -L "$CONFIG" ] && echo yes || echo no)"
assert_eq "symlinked config: the target gets the setting" "False" "$(version_check "$SCRATCH_HOME/dotfiles/herdr.toml")"
teardown

test_summary
