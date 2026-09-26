#!/bin/bash
#
# Unit tests for install/config/nvim.sh: setting up each user's Neovim from
# the ohmydebn-neovim-plugins package. A new user gets the package's config and
# plugins; an existing one (the old LazyVim v14 setup with its pins) is
# migrated once; and whenever the package ships a new tested plugin set,
# OhMyDebn's plugins, parsers and Mason tools are refreshed in the user's own
# directories while anything the user added stays, with what's replaced kept
# in a single backup directory.
#
# The package is a small fake one in a scratch directory (plugins are real
# git repos, so commit checks are real); dpkg and the headline are mocked,
# HOME is a scratch directory, and OhMyDebn's own config files come from
# this repo.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/nvim.sh ==="

# make_repo <dir> <content>: a one-commit git repo; prints the commit.
make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  echo "$2" >"$1/plugin.lua"
  git -C "$1" add plugin.lua
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"
  git -C "$1" rev-parse HEAD
}

# make_seed <dir> <plugin-version>: a fake package tree with two plugins
# (alpha, beta), a parser and a Mason tool (stylua) at that version.
make_seed() {
  local seed="$1" version="$2" alpha beta
  rm -rf "$seed"
  mkdir -p "$seed/config/lua/plugins" "$seed/data/site/parser" "$seed/data/mason/packages/stylua" \
    "$seed/data/mason/bin" "$seed/data/mason/share" "$seed/data/mason/registries/github"
  cp "$REPO_ROOT/config/nvim/lua/plugins/ohmydebn-offline.lua" "$seed/config/lua/plugins/"
  mkdir -p "$seed/config/lua/config"
  cp "$REPO_ROOT/config/nvim/lua/config/"*.lua "$seed/config/lua/config/"
  cp "$REPO_ROOT/config/nvim/lazyvim.json" "$seed/config/"
  alpha=$(make_repo "$seed/data/lazy/alpha" "alpha $version")
  beta=$(make_repo "$seed/data/lazy/beta" "beta $version")
  printf '{ "alpha": { "branch": "main", "commit": "%s" }, "beta": { "branch": "main", "commit": "%s" } }\n' \
    "$alpha" "$beta" >"$seed/config/lazy-lock.json"
  echo "lua parser $version" >"$seed/data/site/parser/lua.so"
  echo "{\"name\": \"stylua\", \"version\": \"$version\"}" >"$seed/data/mason/packages/stylua/mason-receipt.json"
  ln -s ../packages/stylua/stylua "$seed/data/mason/bin/stylua"
  echo "registry $version" >"$seed/data/mason/registries/github/registry.json"
}

# setup <installed: yes|no>
setup() {
  mock_init
  [[ "$1" == "yes" ]] && touch "$MOCK_DIR/installed"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn-neovim-plugins" && -f "$MOCK_DIR/installed" ]] && exit 0
exit 1
EOF2
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
mock_log "headline $*"
EOF2
  SCRATCH_HOME=$(mktemp -d)
  SEED="$MOCK_DIR/seed"
  make_seed "$SEED" 1
  CFG="$SCRATCH_HOME/.config/nvim"
  DATA="$SCRATCH_HOME/.local/share/nvim"
  STATE="$SCRATCH_HOME/.local/state/ohmydebn-config"
  sed "s#/usr/lib/ohmydebn-neovim-plugins#$SEED#g; s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" \
    "$REPO_ROOT/install/config/nvim.sh" >"$MOCK_DIR/nvim-patched.sh"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/nvim-patched.sh" </dev/null >"$MOCK_DIR/out" 2>&1
}

head_of() { git -C "$1" rev-parse HEAD 2>/dev/null; }
exists() { [[ -e "$1" || -L "$1" ]] && echo yes || echo no; }
backups() { compgen -G "$DATA/ohmydebn-backup-*" | wc -l; }

# --- package not installed: nothing happens ---
setup no
run
assert_eq "not installed: no config created" "no" "$(exists "$CFG")"
assert_eq "not installed: no plugins installed" "no" "$(exists "$DATA")"
teardown

# --- sourced like the real install: the rest of the install still runs ---
setup no
printf 'source %s\necho after\n' "$MOCK_DIR/nvim-patched.sh" >"$MOCK_DIR/outer.sh"
assert_eq "not installed: sourcing it doesn't end the install" "after" \
  "$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/outer.sh" </dev/null 2>/dev/null)"
teardown

# --- a new user: config and everything else from the package ---
setup yes
run
assert_eq "new user: config comes from the package" "$(jq -S . "$SEED/config/lazy-lock.json")" "$(jq -S . "$CFG/lazy-lock.json" 2>/dev/null)"
assert_eq "new user: theme is linked" "yes" "$([[ -L "$CFG/lua/plugins/theme.lua" ]] && echo yes || echo no)"
assert_eq "new user: offline settings in place" "yes" "$(exists "$CFG/lua/plugins/ohmydebn-offline.lua")"
assert_eq "new user: alpha installed at the tested commit" "$(head_of "$SEED/data/lazy/alpha")" "$(head_of "$DATA/lazy/alpha")"
assert_eq "new user: beta installed at the tested commit" "$(head_of "$SEED/data/lazy/beta")" "$(head_of "$DATA/lazy/beta")"
assert_eq "new user: parser installed" "lua parser 1" "$(cat "$DATA/site/parser/lua.so" 2>/dev/null)"
assert_eq "new user: Mason tool installed" "yes" "$(exists "$DATA/mason/packages/stylua/mason-receipt.json")"
assert_eq "new user: Mason's link installed" "yes" "$([[ -L "$DATA/mason/bin/stylua" ]] && echo yes || echo no)"
assert_eq "new user: Mason registry snapshot installed" "registry 1" "$(cat "$DATA/mason/registries/github/registry.json" 2>/dev/null)"
assert_eq "new user: nothing to back up" "0" "$(backups)"
# --- and the next run (the next OhMyDebn update) changes nothing ---
echo "user edit" >>"$DATA/lazy/alpha/plugin.lua"
: >"$MOCK_CALLS"
run
assert_contains "same package: an unchanged set isn't reinstalled" "$(cat "$DATA/lazy/alpha/plugin.lua")" "user edit"
assert_not_contains "same package: nothing announced" "$(cat "$MOCK_CALLS")" "tested neovim plugins"
teardown

# --- a failed install (here jq can't read the lockfile) is retried next time ---
setup yes
mock_bin jq <<'EOF2'
#!/bin/bash
exit 1
EOF2
run
assert_eq "failed install: no plugins installed" "no" "$(exists "$DATA/lazy/alpha")"
assert_eq "failed install: not marked done" "no" "$(exists "$STATE/nvim-plugins-seeded")"
assert_contains "failed install: says it will retry" "$(cat "$MOCK_DIR/out")" "next OhMyDebn update will try again"
rm "$MOCK_BIN/jq"
run
assert_eq "failed install: the next run installs the plugins" "$(head_of "$SEED/data/lazy/alpha")" "$(head_of "$DATA/lazy/alpha")"
assert_eq "failed install: the next run marks it done" "yes" "$(exists "$STATE/nvim-plugins-seeded")"
teardown

# --- an existing 4.8.0 user: pins set aside, plugins refreshed, own stuff kept ---
setup yes
mkdir -p "$CFG/lua/plugins" "$CFG/lua/config" "$DATA/mason/packages/stylua" "$DATA/mason/packages/pyright" "$STATE"
printf 'return { { "LazyVim/LazyVim", version = "14.15.0" } }\n' >"$CFG/lua/plugins/core.lua"
echo 'return {}' >"$CFG/lua/plugins/treesitter.lua"
echo 'return {}' >"$CFG/lua/plugins/gitsigns.lua"
echo 'return { "me/my-plugin" }' >"$CFG/lua/plugins/mine.lua"
cp "$REPO_ROOT/config/nvim/lazyvim.json" "$CFG/"
cat >"$CFG/lua/config/lazy.lua" <<'EOF2'
require("lazy").setup({
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  },
})
EOF2
touch "$STATE/nvim-transparency-20260308"
OLD_ALPHA=$(make_repo "$DATA/lazy/alpha" "alpha old")
MINE=$(make_repo "$DATA/lazy/my-plugin" "mine")
printf '{ "alpha": { "branch": "main", "commit": "%s" }, "my-plugin": { "branch": "main", "commit": "%s" } }\n' \
  "$OLD_ALPHA" "$MINE" >"$CFG/lazy-lock.json"
echo '{"name": "stylua", "version": "0"}' >"$DATA/mason/packages/stylua/mason-receipt.json"
echo '{"name": "pyright"}' >"$DATA/mason/packages/pyright/mason-receipt.json"
mkdir -p "$DATA/site/parser"
echo "python parser" >"$DATA/site/parser/python.so"
run
assert_eq "migration: LazyVim v14 pin set aside" "no" "$(exists "$CFG/lua/plugins/core.lua")"
assert_eq "migration: the pin is kept, renamed" "1" "$(compgen -G "$CFG/lua/plugins/core.lua.disabled-*" | wc -l)"
assert_eq "migration: treesitter pin set aside" "no" "$(exists "$CFG/lua/plugins/treesitter.lua")"
assert_eq "migration: gitsigns pin set aside" "no" "$(exists "$CFG/lua/plugins/gitsigns.lua")"
assert_eq "migration: the user's own plugin spec stays" "yes" "$(exists "$CFG/lua/plugins/mine.lua")"
assert_contains "migration: lazy.nvim's update checker turned off" "$(cat "$CFG/lua/config/lazy.lua")" "enabled = false, -- OhMyDebn ships tested plugin versions"
assert_not_contains "migration: no update checker left on" "$(cat "$CFG/lua/config/lazy.lua")" "enabled = true"
assert_eq "migration: offline settings in place" "yes" "$(exists "$CFG/lua/plugins/ohmydebn-offline.lua")"
assert_eq "refresh: outdated alpha replaced by the tested one" "$(head_of "$SEED/data/lazy/alpha")" "$(head_of "$DATA/lazy/alpha")"
assert_eq "refresh: the old alpha is in the backup" "$OLD_ALPHA" "$(head_of "$DATA"/ohmydebn-backup-*/lazy/alpha)"
assert_eq "refresh: the user's own plugin untouched" "$MINE" "$(head_of "$DATA/lazy/my-plugin")"
assert_eq "refresh: lockfile has the tested alpha" "$(head_of "$SEED/data/lazy/alpha")" "$(jq -r .alpha.commit "$CFG/lazy-lock.json")"
assert_eq "refresh: lockfile gains beta" "$(head_of "$SEED/data/lazy/beta")" "$(jq -r .beta.commit "$CFG/lazy-lock.json")"
assert_eq "refresh: lockfile keeps the user's own plugin" "$MINE" "$(jq -r '."my-plugin".commit' "$CFG/lazy-lock.json")"
assert_eq "refresh: outdated Mason tool replaced" "1" "$(jq -r .version "$DATA/mason/packages/stylua/mason-receipt.json")"
assert_eq "refresh: the old Mason tool is in the backup" "0" "$(jq -r .version "$DATA"/ohmydebn-backup-*/mason/stylua/mason-receipt.json)"
assert_eq "refresh: the user's own Mason tool untouched" "yes" "$(exists "$DATA/mason/packages/pyright/mason-receipt.json")"
assert_eq "refresh: the user's own parser untouched" "python parser" "$(cat "$DATA/site/parser/python.so")"
assert_eq "refresh: one backup directory" "1" "$(backups)"

# --- a later package with a new tested set: refreshed again, one backup kept ---
make_seed "$SEED" 2
sleep 1 # backup directories are named by the second
run
assert_eq "new set: alpha moved to the new tested commit" "$(head_of "$SEED/data/lazy/alpha")" "$(head_of "$DATA/lazy/alpha")"
assert_eq "new set: parser updated" "lua parser 2" "$(cat "$DATA/site/parser/lua.so")"
assert_eq "new set: still exactly one backup directory" "1" "$(backups)"
assert_contains "new set: the backup holds what this refresh replaced" "$(cat "$DATA"/ohmydebn-backup-*/lazy/alpha/plugin.lua)" "alpha 1"
assert_eq "new set: the user's own plugin still untouched" "$MINE" "$(head_of "$DATA/lazy/my-plugin")"
assert_eq "new set: the migration isn't repeated" "1" "$(compgen -G "$CFG/lua/plugins/core.lua.disabled-*" | wc -l)"
teardown

test_summary
