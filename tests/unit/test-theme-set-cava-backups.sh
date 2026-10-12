#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-cava's backups. It used to copy the
# whole cava config before every theme switch, piling up
# config.backup.<time> files without limit (151 on one machine). Now it
# keeps one backup, config.backup-before-ohmydebn: the config as it was
# before OhMyDebn first changed it. The per-switch backups already there
# are folded in: the oldest becomes that backup, the rest are removed.
# HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-cava: backups ==="

COLORS="$REPO_ROOT/themes/ohmydebn/colors.toml"

setup() {
  mock_init
  H="$MOCK_DIR/home"
  CAVA="$H/.config/cava"
  mkdir -p "$CAVA" "$H/.config/ohmydebn/current/theme"
  cp "$COLORS" "$H/.config/ohmydebn/current/theme/colors.toml"
  printf '[general]\nframerate = 60\n\n[color]\ngradient = 0\n' >"$CAVA/config"
}

run() {
  HOME="$H" bash "$REPO_ROOT/bin/ohmydebn-theme-set-cava" </dev/null >/dev/null 2>&1
  STATUS=$?
}

backups() { (cd "$CAVA" && ls -1 config.backup* 2>/dev/null | tr '\n' ' '); }

# A first theme switch: the config as it was is backed up, once.
setup
ORIGINAL=$(cat "$CAVA/config")
run
assert_eq "first switch: exits 0" "0" "$STATUS"
assert_eq "first switch: one backup, of the config before OhMyDebn changed it" "config.backup-before-ohmydebn " "$(backups)"
assert_eq "first switch: the backup is the untouched original" "$ORIGINAL" "$(cat "$CAVA/config.backup-before-ohmydebn")"
assert_contains "first switch: the theme's colors went in" "$(cat "$CAVA/config")" "gradient_color_1"
run
run
assert_eq "more switches: still that one backup, nothing new" "config.backup-before-ohmydebn " "$(backups)"
assert_eq "more switches: the backup is still the original" "$ORIGINAL" "$(cat "$CAVA/config.backup-before-ohmydebn")"
mock_cleanup

# A machine with per-switch backups from before: the oldest (the config
# before OhMyDebn's first change) becomes the one backup, the rest go.
setup
echo "the user's own config" >"$CAVA/config.backup.20260101-090000"
for t in 20260201-090000 20260301-090000 20261001-090000; do echo "an OhMyDebn-colored copy" >"$CAVA/config.backup.$t"; done
run
assert_eq "old backups: folded into one" "config.backup-before-ohmydebn " "$(backups)"
assert_eq "old backups: the oldest one is kept as the backup" "the user's own config" "$(cat "$CAVA/config.backup-before-ohmydebn")"
mock_cleanup

test_summary
