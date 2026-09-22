#!/bin/bash
#
# Unit tests for install/config/ohmydebn-ai-skill.sh - linking the packaged
# OhMyDebn skill into each AI agent's user-level skills directory. The
# previous version only linked Claude Code's and Antigravity's directories
# (on the mistaken assumption every tool reads ~/.claude/skills - Pi
# doesn't), and guarded each with a one-time state marker, so a removed
# link never came back. This pins down the new shape: the full set of
# directories, self-healing on re-run, and not clobbering a user's own
# file at a link path.
#
# Everything runs under a scratch HOME with the skill source patched to a
# scratch directory, so nothing here touches the real ~/.claude etc.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/ohmydebn-ai-skill.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/ohmydebn-ai-skill.sh ==="

EXPECTED_DIRS=(".claude/skills" ".gemini/antigravity/global_skills" ".agents/skills")

setup() {
  mock_init
  mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF2
  SCRATCH_HOME=$(mktemp -d)
  SKILL_SRC="$MOCK_DIR/ohmydebn-skill"
  mkdir -p "$SKILL_SRC"
  echo "---" >"$SKILL_SRC/SKILL.md"
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#SKILL_SRC=/usr/share/ohmydebn/config/ohmydebn-skill#SKILL_SRC=$SKILL_SRC#" \
    "$SCRIPT" >"$MOCK_DIR/patched.sh"
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

# Runs under -e like the real install (install.sh sets it and sources the
# config layer), so any failing command here is a real install-breaker.
run_script() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash -e "$MOCK_DIR/patched.sh" >"$MOCK_DIR/output" 2>&1
  echo $?
}

assert_all_links() {
  local desc="$1"
  for d in "${EXPECTED_DIRS[@]}"; do
    assert_eq "$desc: $d/ohmydebn -> skill source" "$SKILL_SRC" "$(readlink "$SCRATCH_HOME/$d/ohmydebn" 2>/dev/null)"
  done
}

# Scenario 1: fresh HOME -> every directory created and linked, one headline
setup
EXIT_CODE=$(run_script)
assert_eq "fresh: exits 0" "0" "$EXIT_CODE"
assert_all_links "fresh"
assert_eq "fresh: exactly one headline" "1" "$(grep -c ohmydebn-headline "$MOCK_CALLS")"
assert_eq "fresh: skill readable through the Pi/OpenCode shared link" "---" "$(cat "$SCRATCH_HOME/.agents/skills/ohmydebn/SKILL.md")"
teardown

# Scenario 2: re-run with everything in place -> silent no-op
setup
run_script >/dev/null
: >"$MOCK_CALLS"
EXIT_CODE=$(run_script)
assert_eq "re-run: exits 0" "0" "$EXIT_CODE"
assert_eq "re-run: no headline" "" "$(cat "$MOCK_CALLS")"
assert_eq "re-run: no output at all" "" "$(cat "$MOCK_DIR/output")"
assert_all_links "re-run"
teardown

# Scenario 3: one link removed (e.g. an agent's uninstaller cleaned its dir) -> only that one comes back
setup
run_script >/dev/null
rm "$SCRATCH_HOME/.agents/skills/ohmydebn"
: >"$MOCK_CALLS"
EXIT_CODE=$(run_script)
assert_eq "self-heal: exits 0" "0" "$EXIT_CODE"
assert_all_links "self-heal"
assert_eq "self-heal: only the missing link was (re)made" "1" "$(grep -c '^Linking ' "$MOCK_DIR/output")"
assert_contains "self-heal: it was the .agents one" "$(cat "$MOCK_DIR/output")" "Linking $SCRATCH_HOME/.agents/skills/ohmydebn"
teardown

# Scenario 4: stale link pointing somewhere else (e.g. an old checkout path) -> repointed, not nested inside
setup
mkdir -p "$SCRATCH_HOME/.claude/skills" "$MOCK_DIR/old-location"
ln -s "$MOCK_DIR/old-location" "$SCRATCH_HOME/.claude/skills/ohmydebn"
EXIT_CODE=$(run_script)
assert_eq "stale link: exits 0" "0" "$EXIT_CODE"
assert_all_links "stale link"
assert_eq "stale link: nothing created inside the old target" "" "$(ls -A "$MOCK_DIR/old-location")"
teardown

# Scenario 5: a real directory already at a link path (user's own skill) -> left alone, others still linked, still exit 0
setup
mkdir -p "$SCRATCH_HOME/.claude/skills/ohmydebn"
echo "mine" >"$SCRATCH_HOME/.claude/skills/ohmydebn/SKILL.md"
EXIT_CODE=$(run_script)
assert_eq "user dir in the way: exits 0 (must not abort a set -e install)" "0" "$EXIT_CODE"
assert_eq "user dir in the way: user's file untouched" "mine" "$(cat "$SCRATCH_HOME/.claude/skills/ohmydebn/SKILL.md")"
assert_eq "user dir in the way: still a real directory, not a link" "no" "$([[ -L "$SCRATCH_HOME/.claude/skills/ohmydebn" ]] && echo yes || echo no)"
assert_contains "user dir in the way: explains it" "$(cat "$MOCK_DIR/output")" "is not a symlink - leaving it alone"
assert_eq "user dir in the way: .agents link still made" "$SKILL_SRC" "$(readlink "$SCRATCH_HOME/.agents/skills/ohmydebn")"
assert_eq "user dir in the way: antigravity link still made" "$SKILL_SRC" "$(readlink "$SCRATCH_HOME/.gemini/antigravity/global_skills/ohmydebn")"
teardown

# Scenario 6: legacy install - old dated state markers present, links already there -> nothing to do, markers ignored
setup
run_script >/dev/null
mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
touch "$SCRATCH_HOME/.local/state/ohmydebn-config/skill-20260116" "$SCRATCH_HOME/.local/state/ohmydebn-config/skill-antigravity-20260125"
rm "$SCRATCH_HOME/.agents/skills/ohmydebn"   # a legacy install never had this one
EXIT_CODE=$(run_script)
assert_eq "legacy markers: exits 0" "0" "$EXIT_CODE"
assert_eq "legacy markers: new .agents link added despite old markers" "$SKILL_SRC" "$(readlink "$SCRATCH_HOME/.agents/skills/ohmydebn")"
teardown

test_summary
