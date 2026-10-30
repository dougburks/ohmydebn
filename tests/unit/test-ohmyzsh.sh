#!/bin/bash
#
# Unit tests for install/config/ohmyzsh.sh. Oh My Zsh now comes from the
# ohmydebn-ohmyzsh package in /usr/share/oh-my-zsh instead of a download
# into each user's ~/.oh-my-zsh (which then updated itself from Oh My
# Zsh's master branch), so an existing ~/.zshrc is moved onto it once:
# OhMyDebn's own ZSH line is replaced, ZSH_CUSTOM keeps the user's
# ~/.oh-my-zsh/custom, and anything else is left alone. It waits for the
# package, so a .zshrc is never pointed at a copy that isn't there.
#
# Also the one-time repair, kept from the download's days, for installs
# whose OhMyDebn .zshrc the old installer had moved to
# ~/.zshrc.pre-oh-my-zsh.
#
# /usr/share/oh-my-zsh is a scratch directory, HOME is another, and dpkg
# and the headline are stand-ins.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/ohmyzsh.sh ==="

setup() {
  mock_init
  H="$MOCK_DIR/home"
  OMZ="$MOCK_DIR/usr-share-oh-my-zsh"
  STATE="$H/.local/state/ohmydebn-config/ohmyzsh-packaged-20261027"
  mkdir -p "$H" "$OMZ"
  : >"$OMZ/oh-my-zsh.sh"
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 0
STUB
  mock_bin ohmydebn-headline <<'STUB'
#!/bin/bash
mock_log "headline $*"
STUB
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/oh-my-zsh#$OMZ#g" \
    "$REPO_ROOT/install/config/ohmyzsh.sh" >"$MOCK_DIR/ohmyzsh.sh"
}

run() {
  HOME="$H" PATH="$(mock_path)" bash -e -c "source '$MOCK_DIR/ohmyzsh.sh'" </dev/null >/dev/null 2>&1
  STATUS=$?
}
exists() { [[ -e "$1" || -L "$1" ]] && echo yes || echo no; }

# The lines of the .zshrc OhMyDebn shipped before 4.14.0 that matter here.
# shellcheck disable=SC2016 # .zshrc text, not expanded here
OLD_ZSHRC='# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
eval "$(starship init zsh)"'

# --- an existing OhMyDebn .zshrc: moved onto the package, once ---
setup
printf '%s\n' "$OLD_ZSHRC" >"$H/.zshrc"
chmod 600 "$H/.zshrc"
run
assert_eq "existing .zshrc: exits 0" "0" "$STATUS"
assert_eq "existing .zshrc: ZSH is the packaged copy" "export ZSH=\"$OMZ\"" "$(grep '^export ZSH=' "$H/.zshrc")"
# shellcheck disable=SC2016
assert_eq "existing .zshrc: the user's custom/ still loads" 'export ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"' \
  "$(grep '^export ZSH_CUSTOM=' "$H/.zshrc")"
assert_eq "existing .zshrc: nothing else changed" "$(printf '%s\n' "$OLD_ZSHRC" | grep -v '^export ZSH=')" \
  "$(grep -v '^export ZSH' "$H/.zshrc")"
assert_eq "existing .zshrc: the ZSH settings stay where the old line was" "2" "$(grep -n '^export ZSH=' "$H/.zshrc" | cut -d: -f1)"
assert_eq "existing .zshrc: keeps its permissions" "600" "$(stat -c %a "$H/.zshrc")"
assert_eq "existing .zshrc: the previous one is kept as a backup" "$OLD_ZSHRC" "$(cat "$H"/.zshrc-backup-* 2>/dev/null)"
assert_contains "existing .zshrc: says what it did" "$(cat "$MOCK_CALLS")" "packaged Oh My Zsh"
assert_eq "existing .zshrc: marked done" "yes" "$(exists "$STATE")"
# The user then points it back at their own copy: that's theirs to keep.
sed -i "s#^export ZSH=.*#export ZSH=\"\$HOME/.oh-my-zsh\"#" "$H/.zshrc"
run
assert_eq "runs once: a later change of the user's is kept" 1 "$(grep -cxF 'export ZSH="$HOME/.oh-my-zsh"' "$H/.zshrc")"
mock_cleanup

# --- the package isn't there yet: nothing changes, and it's tried again ---
setup
rm "$OMZ/oh-my-zsh.sh"
printf '%s\n' "$OLD_ZSHRC" >"$H/.zshrc"
run
assert_eq "no package: .zshrc untouched" "$OLD_ZSHRC" "$(cat "$H/.zshrc")"
assert_eq "no package: not marked done" "no" "$(exists "$STATE")"
: >"$OMZ/oh-my-zsh.sh"
run
assert_eq "package installed later: moved then" "export ZSH=\"$OMZ\"" "$(grep '^export ZSH=' "$H/.zshrc")"
mock_cleanup

# --- a ZSH line of the user's own is left alone ---
setup
# shellcheck disable=SC2016
printf '%s\n' 'export ZSH="$HOME/src/ohmyzsh"' 'source $ZSH/oh-my-zsh.sh' >"$H/.zshrc"
run
# shellcheck disable=SC2016
assert_eq "own ZSH line: untouched" 'export ZSH="$HOME/src/ohmyzsh"' "$(grep '^export ZSH=' "$H/.zshrc")"
assert_eq "own ZSH line: no backup made" "" "$(ls "$H"/.zshrc-backup-* 2>/dev/null)"
assert_eq "own ZSH line: marked done" "yes" "$(exists "$STATE")"
mock_cleanup

# --- a symlinked .zshrc (a dotfiles repo's) is left alone ---
setup
mkdir -p "$H/dotfiles"
printf '%s\n' "$OLD_ZSHRC" >"$H/dotfiles/zshrc"
ln -s "$H/dotfiles/zshrc" "$H/.zshrc"
run
assert_eq "symlinked .zshrc: still a link" "yes" "$([[ -L "$H/.zshrc" ]] && echo yes || echo no)"
assert_eq "symlinked .zshrc: its file untouched" "$OLD_ZSHRC" "$(cat "$H/dotfiles/zshrc")"
mock_cleanup

# --- a new install: no .zshrc yet (zsh.sh writes the new one after this) ---
setup
run
assert_eq "new install: exits 0" "0" "$STATUS"
assert_eq "new install: no .zshrc created" "no" "$(exists "$H/.zshrc")"
assert_eq "new install: marked done" "yes" "$(exists "$STATE")"
mock_cleanup

# --- the .zshrc OhMyDebn ships now needs no move ---
setup
cp "$REPO_ROOT/config/.zshrc" "$H/.zshrc"
run
assert_eq "today's .zshrc: unchanged" "$(cat "$REPO_ROOT/config/.zshrc")" "$(cat "$H/.zshrc")"
assert_contains "today's .zshrc: loads the packaged copy" "$(cat "$H/.zshrc")" 'export ZSH="/usr/share/oh-my-zsh"'
mock_cleanup

# --- the old repair: OhMyDebn's .zshrc is restored once, then moved too ---
setup
printf '%s\n' "$OLD_ZSHRC" >"$H/.zshrc.pre-oh-my-zsh"
echo 'export PATH="/usr/share/ohmydebn/bin:$PATH"' >"$H/.zshrc"
run
assert_contains "repair: OhMyDebn's .zshrc is back" "$(cat "$H/.zshrc")" 'eval "$(starship init zsh)"'
assert_eq "repair: and moved onto the package" "export ZSH=\"$OMZ\"" "$(grep '^export ZSH=' "$H/.zshrc")"
assert_contains "repair: the PATH-only stub is kept as a backup" "$(cat "$H"/.zshrc-backup-* 2>/dev/null)" "PATH"
echo "my own change" >>"$H/.zshrc"
printf '%s\n' "$OLD_ZSHRC" >"$H/.zshrc.pre-oh-my-zsh"
run
assert_contains "repair: runs only once" "$(cat "$H/.zshrc")" "my own change"
mock_cleanup

# A .zshrc that already runs Oh My Zsh isn't replaced by the repair.
setup
printf '%s\n' "$OLD_ZSHRC" >"$H/.zshrc.pre-oh-my-zsh"
echo 'source $ZSH/oh-my-zsh.sh # the user'"'"'s own' >"$H/.zshrc"
run
assert_contains "no repair when .zshrc already runs Oh My Zsh" "$(cat "$H/.zshrc")" "the user's own"
mock_cleanup

test_summary
