#!/bin/bash
#
# Unit tests for install/config/alacritty.sh's two config formats. The
# config it writes uses Alacritty 0.14+'s keys ([general] import,
# [terminal] shell), rewritten to the pre-0.14 form (top-level import,
# [shell] program) when alacritty is older, such as Linux Mint 22's
# 0.13.2. Nothing converted it back once alacritty itself was upgraded
# past 0.14 (Mint 22 to Mint 27's 0.16), so every Alacritty window warned
# that import and shell were deprecated. Each step is sourced under set -e,
# as install.sh does, with dpkg-query answering MOCK_ALACRITTY_VERSION and
# version comparisons left to the real dpkg.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/alacritty.sh: old and new config formats ==="

CONFIG_REL=.config/alacritty/alacritty.toml

setup() {
  mock_init
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/state"
  touch "$SCRATCH_HOME/.local/state/ohmydebn" # an update, not a first install
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[ "$1" = "-s" ] && exit 0
[ "$1" = "--compare-versions" ] && exec /usr/bin/dpkg "$@"
exit 1
EOF2
  mock_bin dpkg-query <<'EOF2'
#!/bin/bash
echo "$MOCK_ALACRITTY_VERSION"
EOF2
  for cmd in ohmydebn-headline gsettings; do
    printf '#!/bin/bash\nmock_log "%s $*"\n' "$cmd" | mock_bin "$cmd"
  done
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" \
    "$REPO_ROOT/install/config/alacritty.sh" >"$MOCK_DIR/step.sh"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# run_step <alacritty version>
run_step() {
  : >"$MOCK_CALLS"
  OUT=$(MOCK_ALACRITTY_VERSION="$1" HOME="$SCRATCH_HOME" PATH="$(mock_path)" \
    bash -c 'set -e; source "$1"; echo "run finished"' _ "$MOCK_DIR/step.sh" </dev/null 2>&1)
  CALLS=$(cat "$MOCK_CALLS")
}

config() { cat "$SCRATCH_HOME/$CONFIG_REL"; }
backups() { find "$SCRATCH_HOME/.config/alacritty" -name 'alacritty.toml.backup-*' | wc -l; }
# toml_get <dotted key>: the value alacritty would read, from Python's parser
toml_get() {
  python3 -c 'import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
for k in sys.argv[2].split("."):
    d = d[k]
print(d)' "$SCRATCH_HOME/$CONFIG_REL" "$1" 2>&1
}

# The config as OhMyDebn wrote it on Mint 22's alacritty 0.13.2, after the
# theme added its decorations line: the case reported from Mint 27.
write_mint22_config() {
  mkdir -p "$SCRATCH_HOME/.config/alacritty"
  cat >"$SCRATCH_HOME/$CONFIG_REL" <<'EOF2'
import = [
  "~/.config/ohmydebn/current/theme/alacritty.toml"
]

[env]
TERM = "xterm-256color"

[shell]
program = "/usr/bin/zsh"

[window]
decorations_theme_variant = "Dark"
opacity = 0.97
EOF2
}

# --- a new install: the format follows the alacritty it finds ---
setup
run_step 0.15.1-1
assert_contains "new install, 0.15: runs through" "$OUT" "run finished"
assert_eq "new install, 0.15: OhMyDebn's config as shipped" "$(cat "$REPO_ROOT/config/alacritty/alacritty.toml")" "$(config)"
assert_eq "new install, 0.15: no backup" "0" "$(backups)"
teardown

setup
run_step 0.13.2-1
assert_eq "new install, 0.13: top-level import" "['~/.config/ohmydebn/current/theme/alacritty.toml']" "$(toml_get import)"
assert_eq "new install, 0.13: [shell] program" "/usr/bin/zsh" "$(toml_get shell.program)"
assert_not_contains "new install, 0.13: no [general]" "$(config)" "[general]"
teardown

# --- a Mint 22 config after alacritty is upgraded to 0.16 ---
setup
write_mint22_config
ORIGINAL=$(config)
run_step 0.16.1-1
assert_contains "Mint 22 config on 0.16: runs through" "$OUT" "run finished"
assert_contains "Mint 22 config on 0.16: says so" "$CALLS" "ohmydebn-headline Updating alacritty config for Alacritty 0.16.1-1"
assert_eq "Mint 22 config on 0.16: general.import" "['~/.config/ohmydebn/current/theme/alacritty.toml']" "$(toml_get general.import)"
assert_eq "Mint 22 config on 0.16: terminal.shell" "/usr/bin/zsh" "$(toml_get terminal.shell)"
assert_not_contains "Mint 22 config on 0.16: no [shell] left" "$(config)" "[shell]"
assert_not_contains "Mint 22 config on 0.16: no program key left" "$(config)" "program ="
assert_eq "Mint 22 config on 0.16: the theme's window setting kept" "Dark" "$(toml_get window.decorations_theme_variant)"
assert_eq "Mint 22 config on 0.16: env kept" "xterm-256color" "$(toml_get env.TERM)"
assert_eq "Mint 22 config on 0.16: one backup" "1" "$(backups)"
assert_eq "Mint 22 config on 0.16: the backup is the old config" "$ORIGINAL" \
  "$(cat "$SCRATCH_HOME"/.config/alacritty/alacritty.toml.backup-*)"

# The next update: already converted, so nothing changes. A second
# [general] table here would be invalid TOML, and alacritty would refuse it.
CONVERTED=$(config)
run_step 0.16.1-1
assert_eq "second update: config unchanged" "$CONVERTED" "$(config)"
assert_eq "second update: no new backup" "1" "$(backups)"
assert_not_contains "second update: says nothing" "$CALLS" "Updating alacritty config"
teardown

# Written on 0.13, then upgraded: exactly OhMyDebn's shipped config again.
setup
run_step 0.13.2-1
run_step 0.16.1-1
assert_eq "written on 0.13, updated on 0.16: the shipped config" "$(cat "$REPO_ROOT/config/alacritty/alacritty.toml")" "$(config)"
teardown

# --- left alone ---
setup
write_mint22_config
ORIGINAL=$(config)
run_step 0.13.2-1
assert_eq "Mint 22 config, still on 0.13: unchanged" "$ORIGINAL" "$(config)"
assert_eq "Mint 22 config, still on 0.13: no backup" "0" "$(backups)"
teardown

# Only [shell] is old (import already under [general]): only it changes.
setup
mkdir -p "$SCRATCH_HOME/.config/alacritty"
printf '[general]\nimport = ["a.toml"]\nlive_config_reload = true\n\n[shell]\nprogram = "/bin/bash"\n' >"$SCRATCH_HOME/$CONFIG_REL"
run_step 0.15.1-1
assert_eq "old [shell] only: general.import kept" "['a.toml']" "$(toml_get general.import)"
assert_eq "old [shell] only: one [general]" "1" "$(grep -c '^\[general\]' "$SCRATCH_HOME/$CONFIG_REL")"
assert_eq "old [shell] only: terminal.shell" "/bin/bash" "$(toml_get terminal.shell)"
teardown

# Top-level keys after the import move into [general] with it, where
# 0.14+ reads them.
setup
mkdir -p "$SCRATCH_HOME/.config/alacritty"
printf 'import = ["a.toml"]\nlive_config_reload = true\n\n[window]\nopacity = 0.9\n' >"$SCRATCH_HOME/$CONFIG_REL"
run_step 0.15.1-1
assert_eq "old import only: general.live_config_reload" "True" "$(toml_get general.live_config_reload)"
assert_eq "old import only: window untouched" "0.9" "$(toml_get window.opacity)"
teardown

# A linked config stays linked.
setup
mkdir -p "$SCRATCH_HOME/.config/alacritty" "$SCRATCH_HOME/dotfiles"
write_mint22_config
mv "$SCRATCH_HOME/$CONFIG_REL" "$SCRATCH_HOME/dotfiles/alacritty.toml"
ln -s "$SCRATCH_HOME/dotfiles/alacritty.toml" "$SCRATCH_HOME/$CONFIG_REL"
run_step 0.16.1-1
assert_eq "linked config: still a link" "yes" "$([ -L "$SCRATCH_HOME/$CONFIG_REL" ] && echo yes || echo no)"
assert_eq "linked config: its target converted" "/usr/bin/zsh" "$(toml_get terminal.shell)"
teardown

test_summary
