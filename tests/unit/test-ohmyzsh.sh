#!/bin/bash
#
# Unit tests for install/config/ohmyzsh.sh. When the first install's Oh My
# Zsh download failed and a later update's worked, the installer moved
# OhMyDebn's .zshrc (written by zsh.sh in between) to ~/.zshrc.pre-oh-my-zsh
# and wrote its own template, which this step then moved away too - leaving
# no Oh My Zsh config, Starship or aliases. Now it runs the installer with
# --keep-zshrc and only moves a template the installer wrote. A one-time
# repair puts OhMyDebn's .zshrc back on installs that already lost it.
#
# The installer is a stand-in that does what the real one does with
# ~/.zshrc (tools/install.sh's setup_zshrc), served by a curl stand-in.
# HOME is a scratch directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/ohmyzsh.sh ==="

setup() {
  mock_init
  H="$MOCK_DIR/home"
  mkdir -p "$H"
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 0
STUB
  mock_bin ohmydebn-headline <<'STUB'
#!/bin/bash
mock_log "headline $*"
STUB
  # The installer, as curl serves it: Oh My Zsh's handling of ~/.zshrc.
  cat >"$MOCK_DIR/installer.sh" <<'INSTALLER'
echo "installer $*" >>"$MOCK_CALLS"
mkdir -p "$HOME/.oh-my-zsh"
keep=no
for arg in "$@"; do [ "$arg" = --keep-zshrc ] && keep=yes; done
if [ -f "$HOME/.zshrc" ]; then
  [ "$keep" = yes ] && exit 0
  mv "$HOME/.zshrc" "$HOME/.zshrc.pre-oh-my-zsh"
fi
echo "source \$ZSH/oh-my-zsh.sh # template" >"$HOME/.zshrc"
INSTALLER
  mock_bin curl <<'STUB'
#!/bin/bash
cat "$MOCK_DIR/installer.sh"
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/install/config/ohmyzsh.sh" >"$MOCK_DIR/ohmyzsh.sh"
}

run() {
  HOME="$H" PATH="$(mock_path)" bash -e -c "source '$MOCK_DIR/ohmyzsh.sh'" </dev/null >/dev/null 2>&1
  STATUS=$?
}
OURS='source $ZSH/oh-my-zsh.sh
eval "$(starship init zsh)"'

# A first install: the template is moved aside for zsh.sh to replace.
setup
run
assert_eq "first install: exits 0" "0" "$STATUS"
assert_contains "the installer keeps an existing .zshrc" "$(cat "$MOCK_CALLS")" "--keep-zshrc"
assert_eq "first install: the template is moved aside" "yes" "$([ -f "$H/.zshrc.oh-my-zsh" ] && echo yes || echo no)"
assert_eq "first install: no .zshrc left for zsh.sh to back up" "no" "$([ -e "$H/.zshrc" ] && echo yes || echo no)"
mock_cleanup

# The download failed on the first install, so OhMyDebn's .zshrc is there
# already; a later update's download works.
setup
printf '%s\n' "$OURS" >"$H/.zshrc"
run
assert_eq "retry: OhMyDebn's .zshrc is kept" "$OURS" "$(cat "$H/.zshrc" 2>/dev/null)"
assert_eq "retry: nothing moved aside" "no" "$([ -e "$H/.zshrc.pre-oh-my-zsh" ] || [ -e "$H/.zshrc.oh-my-zsh" ] && echo yes || echo no)"
mock_cleanup

# An install that already lost it: OhMyDebn's .zshrc is restored once.
setup
mkdir -p "$H/.oh-my-zsh"
printf '%s\n' "$OURS" >"$H/.zshrc.pre-oh-my-zsh"
echo 'export PATH="/usr/share/ohmydebn/bin:$PATH"' >"$H/.zshrc"
run
assert_eq "repair: OhMyDebn's .zshrc is back" "$OURS" "$(cat "$H/.zshrc" 2>/dev/null)"
assert_contains "repair: the PATH-only stub is kept as a backup" "$(cat "$H"/.zshrc-backup-* 2>/dev/null)" "PATH"
echo "my own change" >>"$H/.zshrc"
printf '%s\n' "$OURS" >"$H/.zshrc.pre-oh-my-zsh"
run
assert_contains "repair: runs only once" "$(cat "$H/.zshrc")" "my own change"
mock_cleanup

# A .zshrc that already runs Oh My Zsh is left alone.
setup
mkdir -p "$H/.oh-my-zsh"
printf '%s\n' "$OURS" >"$H/.zshrc.pre-oh-my-zsh"
echo 'source $ZSH/oh-my-zsh.sh # the user'"'"'s own' >"$H/.zshrc"
run
assert_contains "no repair when .zshrc already runs Oh My Zsh" "$(cat "$H/.zshrc")" "the user's own"
mock_cleanup

test_summary
