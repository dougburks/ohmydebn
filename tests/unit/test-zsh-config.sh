#!/bin/bash
#
# Unit tests for install/config/zsh.sh, focused on the two newest
# state-gated blocks: PI_ALIAS_STATE (appends the `pi` alias, same shape as
# the pre-existing GRC_STATE/COLOR_MAN_STATE blocks - deliberately NOT
# baked into config/.zshrc itself, so it doesn't double up on a fresh
# install where ZSHRC_STATE also copies the template) and
# OPENCODE_CLI_ALIAS_STATE (a one-time sed migration of the pre-existing
# `c` alias on installs provisioned before ohmydebn-opencode-cli existed).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/zsh.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/zsh.sh ==="

setup_mocks() {
  mock_bin dpkg <<'EOF'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "zsh" ]] && exit 0
exit 1
EOF
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
echo "ohmydebn-headline $*" >>"$MOCK_CALLS"
EOF
  sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" \
    -e "s#/usr/share/ohmydebn/config/.zshrc#$REPO_ROOT/config/.zshrc#g" \
    "$SCRIPT" >"$MOCK_DIR/zsh-patched.sh"
}

# Scenario 1: brand-new install (no ~/.zshrc, no state dir at all) - the
# template copy (ZSHRC_STATE) and the pi-alias append (PI_ALIAS_STATE) both
# fire in the same run. The `pi` alias must end up in ~/.zshrc exactly once,
# not twice, since it's deliberately absent from config/.zshrc itself.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/zsh-patched.sh" >/dev/null 2>&1
ZSHRC_CONTENT=$(cat "$SCRATCH_HOME/.zshrc")
PI_COUNT=$(grep -Fc "alias pi='$MOCK_BIN/ohmydebn-pi-cli'" "$SCRATCH_HOME/.zshrc")
assert_eq "fresh install: pi alias appears exactly once" "1" "$PI_COUNT"
assert_contains "fresh install: c alias already correct from template" "$ZSHRC_CONTENT" \
  "alias c='/usr/share/ohmydebn/bin/ohmydebn-opencode-cli'"
assert_eq "fresh install: pi-alias state marker written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/pi-alias" ] && echo yes || echo no)"
assert_eq "fresh install: opencode-cli-alias state marker written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/opencode-cli-alias" ] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: a pre-existing install from before this feature - ZSHRC_STATE
# already fired long ago (marker present, real ~/.zshrc already exists with
# the old opencode-cli alias and no pi alias at all). The migration should
# rewrite the old c alias in place, append pi once, and must NOT re-run the
# template copy (no "Configuring Zsh" headline).
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/zshrc-20260116"
cat >"$SCRATCH_HOME/.zshrc" <<'EOF'
# Aliases
alias c='/usr/bin/opencode-cli'
alias ls='/usr/bin/eza -lh --group-directories-first --icons=auto'
EOF
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/zsh-patched.sh" >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
ZSHRC_CONTENT=$(cat "$SCRATCH_HOME/.zshrc")
assert_not_contains "pre-existing install: template copy not re-run" "$CALLS" "Configuring Zsh"
assert_contains "pre-existing install: c alias migrated to wrapper" "$ZSHRC_CONTENT" \
  "alias c='$MOCK_BIN/ohmydebn-opencode-cli'"
assert_not_contains "pre-existing install: old c alias value gone" "$ZSHRC_CONTENT" \
  "alias c='/usr/bin/opencode-cli'"
PI_COUNT=$(grep -Fc "alias pi='$MOCK_BIN/ohmydebn-pi-cli'" "$SCRATCH_HOME/.zshrc")
assert_eq "pre-existing install: pi alias appended exactly once" "1" "$PI_COUNT"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: idempotency - running again on an already-migrated ~/.zshrc
# must not append or rewrite anything a second time.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/zshrc-20260116"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/pi-alias"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/opencode-cli-alias"
cat >"$SCRATCH_HOME/.zshrc" <<'EOF'
# Aliases
alias c='/usr/share/ohmydebn/bin/ohmydebn-opencode-cli'
alias pi='/usr/share/ohmydebn/bin/ohmydebn-pi-cli'
EOF
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/zsh-patched.sh" >/dev/null 2>&1
PI_COUNT=$(grep -c "^alias pi='/usr/share/ohmydebn/bin/ohmydebn-pi-cli'\$" "$SCRATCH_HOME/.zshrc")
C_COUNT=$(grep -c "^alias c='/usr/share/ohmydebn/bin/ohmydebn-opencode-cli'\$" "$SCRATCH_HOME/.zshrc")
assert_eq "already migrated: pi alias still appears exactly once" "1" "$PI_COUNT"
assert_eq "already migrated: c alias still appears exactly once" "1" "$C_COUNT"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
