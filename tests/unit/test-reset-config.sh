#!/bin/bash
#
# Unit tests for bin/ohmydebn-reset-config: it backs up OhMyDebn's app
# config files, clears only the state markers of the install steps that
# write them, reruns the config layer (with errexit, as install.sh does) and
# reapplies the current theme. Offline, Oh My Zsh can't be downloaded
# again, so the previous copy goes back. It used to delete every state marker and
# rerun the setup as a new install, which also reset the panel,
# extensions, keybindings, firewall, theme and default apps.
#
# HOME is a scratch directory, and ohmydebn.sh and ohmydebn-theme-set are
# stand-ins, so nothing here touches the real config or desktop.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-reset-config"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-reset-config ==="

# setup <stand-in ohmydebn.sh body>
setup() {
  mock_init
  H="$MOCK_DIR/home"
  S="$H/.local/state"
  mkdir -p "$S/ohmydebn-config" "$S/ohmydebn-logs" "$H/.config/btop" "$H/.config/ohmydebn/current"
  # Markers a reset must keep: install complete, panel, firewall, keybindings, gTile.
  : >"$S/ohmydebn"
  : >"$S/ohmydebn-panel"
  : >"$S/ohmydebn-ufw"
  : >"$S/ohmydebn-config/keybinding-20260910"
  : >"$S/ohmydebn-config/gTile-config-20250920"
  : >"$S/ohmydebn-config/nvim-plugins-seeded"
  # Markers of the config files it resets.
  : >"$S/ohmydebn-config/btop-config-20250916"
  : >"$S/ohmydebn-config/zshrc-20260116"
  : >"$S/ohmydebn-config/claude-alias"
  : >"$S/ohmydebn-config/starship-20251109"
  echo log >"$S/ohmydebn-logs/update-1.log"
  echo mine >"$H/.config/btop/btop.conf"
  mkdir -p "$H/.oh-my-zsh"
  echo old >"$H/.oh-my-zsh/oh-my-zsh.sh"
  echo "tokyo-night" >"$H/.config/ohmydebn/current/theme.name"
  printf '%s\n' "$1" >"$MOCK_DIR/ohmydebn.sh"
  mock_bin ohmydebn-theme-set <<'STUB'
#!/bin/bash
mock_log "theme-set $*"
STUB
  mock_bin ohmydebn-headline <<'STUB'
#!/bin/bash
mock_log "headline $*"
STUB
  sed -e "s#/usr/share/ohmydebn/ohmydebn.sh#$MOCK_DIR/ohmydebn.sh#" -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" \
    "$SCRIPT" >"$MOCK_DIR/reset"
}

run() {
  OUTPUT=$(HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/reset" <<<"" 2>&1)
  STATUS=$?
}

# The stand-in config layer reinstalls Oh My Zsh, as it does online.
setup 'echo "config layer ran, skip upgrade=${OHMYDEBN_SKIP_UPGRADE:-no}, reset=${OHMYDEBN_RESET:-no}"
mkdir -p ~/.oh-my-zsh && echo new >~/.oh-my-zsh/oh-my-zsh.sh'
mkdir -p "$H/.config/aether"
echo mine >"$H/.config/aether/theme.toml"
run
assert_eq "reset: exits 0" "0" "$STATUS"
assert_contains "reset: says what it resets" "$OUTPUT" "Alacritty, bat, btop, cava, Neovim, Starship, Oh My Zsh and ~/.zshrc"
assert_contains "reset: says what it leaves alone" "$OUTPUT" "Your desktop, panel, keybindings, theme and default apps are not changed."
assert_contains "reset: reruns the config layer" "$OUTPUT" "config layer ran"
assert_contains "reset: without the full system upgrade an update does" "$OUTPUT" "skip upgrade=1"
assert_contains "reset: tells the final steps it's a reset (no update wording)" "$OUTPUT" "reset=1"
assert_eq "online: the new Oh My Zsh is kept" "new" "$(cat "$H/.oh-my-zsh/oh-my-zsh.sh" 2>/dev/null)"
assert_eq "online: the previous Oh My Zsh stays as a backup" "old" "$(cat "$H"/.oh-my-zsh-backup-*/oh-my-zsh.sh 2>/dev/null)"
assert_not_contains "online: nothing said about keeping the old Oh My Zsh" "$OUTPUT" "your previous one was kept"
assert_eq "reset: Aether's folder is left where it is (OhMyDebn has no default for it)" "mine" "$(cat "$H/.config/aether/theme.toml" 2>/dev/null)"
assert_eq "reset: btop config backed up" "mine" "$(cat "$H"/.config/btop-backup-*/btop.conf 2>/dev/null)"
for marker in btop-config-20250916 zshrc-20260116 claude-alias starship-20251109; do
  assert_eq "reset: config marker $marker cleared (so its step writes the file again)" "no" \
    "$([ -e "$S/ohmydebn-config/$marker" ] && echo yes || echo no)"
done
for marker in ohmydebn ohmydebn-panel ohmydebn-ufw ohmydebn-config/keybinding-20260910 \
  ohmydebn-config/gTile-config-20250920 ohmydebn-config/nvim-plugins-seeded; do
  assert_eq "reset: $marker kept (not a config file this resets)" "yes" \
    "$([ -e "$S/$marker" ] && echo yes || echo no)"
done
assert_eq "reset: update logs kept" "log" "$(cat "$S/ohmydebn-logs/update-1.log" 2>/dev/null)"
assert_eq "reset: the current theme is reapplied (background kept), then the reset says it's complete" \
  "theme-set --keep-background tokyo-night
headline OhMyDebn config reset complete" "$(cat "$MOCK_CALLS")"
mock_cleanup

# Offline: the config layer can't download Oh My Zsh, so ~/.zshrc would
# fail to load it in every new terminal; the previous copy goes back.
setup 'echo "Couldn'"'"'t install Oh My Zsh."'
run
assert_eq "offline: reset exits 0" "0" "$STATUS"
assert_eq "offline: the previous Oh My Zsh is put back" "old" "$(cat "$H/.oh-my-zsh/oh-my-zsh.sh" 2>/dev/null)"
assert_eq "offline: no backup left of it" "" "$(ls -d "$H"/.oh-my-zsh-backup-* 2>/dev/null)"
assert_contains "offline: says so" "$OUTPUT" "Couldn't download a new copy of Oh My Zsh, so your previous one was kept."
assert_eq "offline: the btop config is still reset (only Oh My Zsh goes back)" "mine" \
  "$(cat "$H"/.config/btop-backup-*/btop.conf 2>/dev/null)"
mock_cleanup

# A step that fails stops the config layer, as it does under install.sh.
setup 'false
echo "carried on after a failed step"'
run
assert_not_contains "failed step: the config layer stops there" "$OUTPUT" "carried on after a failed step"
assert_eq "failed step: reset exits non-zero" "1" "$STATUS"
assert_eq "failed step: no theme reapplied over a half-done reset" "" "$(cat "$MOCK_CALLS")"
assert_eq "failed step: the previous Oh My Zsh is put back all the same" "old" "$(cat "$H/.oh-my-zsh/oh-my-zsh.sh" 2>/dev/null)"
mock_cleanup

# Every marker the steps behind those config files use is in the reset's
# list - a marker added to one of these steps later would otherwise leave
# its part of the config unwritten after a reset. That includes the theme
# hooks the reset reapplies: ohmydebn-theme-set-starship's marker was
# missed once, and Starship came back on its built-in prompt.
# nvim-plugins-seeded is the exception: it tracks Neovim's plugin data,
# which a reset keeps.
mapfile -t STEP_MARKERS < <(grep -ohE 'ohmydebn-config/[A-Za-z0-9._-]+|\$NVIM_STATE_DIR/[A-Za-z0-9._-]+' \
  "$REPO_ROOT"/install/config/{bat,btop,zsh,nvim}.sh "$REPO_ROOT"/bin/ohmydebn-theme-set* |
  sed 's#.*/##' | grep -vx 'nvim-plugins-seeded' | sort -u)
LISTED=$(sed -n '/^CONFIG_MARKERS=(/,/)/p' "$SCRIPT")
MISSING=""
for marker in "${STEP_MARKERS[@]}"; do
  grep -qw -- "$marker" <<<"$LISTED" || MISSING+="$marker "
done
assert_eq "every marker of the bat, btop, zsh and nvim steps and the theme hooks is in CONFIG_MARKERS" "" "$MISSING"
assert_eq "the step markers were found at all" "yes" "$([ "${#STEP_MARKERS[@]}" -ge 10 ] && echo yes || echo no)"

test_summary
