#!/bin/bash
#
# Unit tests for install steps that used to stop the whole install. Every
# file under install/ is sourced into install.sh's shell, which runs under
# set -e, so one failing command in a step ends the install or update there,
# and a step whose one-time marker was never written fails the same way on
# every update after. Each step here is sourced exactly that way.
#
# - config/ohmyzsh.sh: a failed Oh My Zsh download ran sh -c "" (which
#   succeeds), then mv ~/.zshrc failed on the file that was never written.
# - config/alacritty.sh: a stray ~/.config/alacritty.toml with no
#   ~/.config/alacritty directory made its mv of that directory fail.
# - config/theme.sh: ln -s of Aether's state link failed when the link
#   already existed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install steps that must not stop the install ==="

setup() {
  mock_init
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
  touch "$SCRATCH_HOME/.local/state/ohmydebn" # an update, not a first install
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" ]] && exit 0
exit 1 # --compare-versions ... lt: not older
EOF2
  mock_bin dpkg-query <<'EOF2'
#!/bin/bash
echo "0.15.1"
EOF2
  for cmd in ohmydebn-headline gsettings ohmydebn-theme-set ohmydebn-theme-set-templates \
    ohmydebn-theme-set-fastfetch ohmydebn-theme-set-neovim ohmydebn-theme-set-colors \
    ohmydebn-theme-set-picker ohmydebn-theme-set-colors-delete; do
    printf '#!/bin/bash\nmock_log "%s $*"\n' "$cmd" | mock_bin "$cmd"
  done
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# run_step <install/config/name.sh>: sourced under set -e, as install.sh does
run_step() {
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" \
    "$REPO_ROOT/install/$1" >"$MOCK_DIR/step.sh"
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash -c 'set -e; source "$1"; echo "run finished"' _ "$MOCK_DIR/step.sh" \
    </dev/null >"$MOCK_DIR/out" 2>&1
  assert_contains "$1: the install carries on past it" "$(cat "$MOCK_DIR/out")" "run finished"
}

# --- ohmyzsh.sh: the download fails ---
setup
printf '#!/bin/bash\nexit 22\n' | mock_bin curl
run_step config/ohmyzsh.sh
assert_contains "ohmyzsh: says the next update will try again" "$(cat "$MOCK_DIR/out")" "will try again"
teardown

# --- ohmyzsh.sh: the download works; its ~/.zshrc is set aside ---
setup
printf '#!/bin/bash\necho "mkdir -p \\$HOME/.oh-my-zsh; echo omz >\\$HOME/.zshrc"\n' | mock_bin curl
run_step config/ohmyzsh.sh
assert_eq "ohmyzsh: installed" "yes" "$([[ -d $SCRATCH_HOME/.oh-my-zsh ]] && echo yes || echo no)"
assert_eq "ohmyzsh: its .zshrc is set aside" "omz" "$(cat "$SCRATCH_HOME/.zshrc.oh-my-zsh" 2>/dev/null)"
teardown

# --- alacritty.sh: ~/.config/alacritty.toml without ~/.config/alacritty ---
setup
mkdir -p "$SCRATCH_HOME/.config"
echo "stray" >"$SCRATCH_HOME/.config/alacritty.toml"
run_step config/alacritty.sh
assert_eq "alacritty: the stray file is backed up" "stray" "$(cat "$SCRATCH_HOME"/.config/alacritty-backup-*/alacritty.toml-backup-* 2>/dev/null)"
assert_eq "alacritty: OhMyDebn's config is put in place" "yes" "$([[ -f $SCRATCH_HOME/.config/alacritty/alacritty.toml ]] && echo yes || echo no)"
teardown

# --- theme.sh: Aether's state link is already there ---
setup
mkdir -p "$SCRATCH_HOME/.local/state/omarchy"
ln -s "$SCRATCH_HOME/.config/ohmydebn/current" "$SCRATCH_HOME/.local/state/omarchy/current"
run_step config/theme.sh
assert_eq "theme: the link still points at OhMyDebn's current theme" "$SCRATCH_HOME/.config/ohmydebn/current" \
  "$(readlink "$SCRATCH_HOME/.local/state/omarchy/current")"
assert_eq "theme: its marker is written" "yes" \
  "$([[ -f $SCRATCH_HOME/.local/state/ohmydebn-config/omarchy-theme-url-handler-20260814 ]] && echo yes || echo no)"
teardown

test_summary
