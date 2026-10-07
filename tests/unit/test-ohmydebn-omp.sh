#!/bin/bash
#
# Unit tests for Oh My Pi (omp, Stencil Labs' fork of Pi): the wrappers
# bin/ohmydebn-omp-cli, -run and -install, which mirror Pi's (the package,
# ohmydebn-oh-my-pi, installs only /usr/lib/ohmydebn-oh-my-pi/omp), and the
# theme hook bin/ohmydebn-theme-set-omp. omp validates a theme against a
# schema that requires every one of its color tokens and rejects unknown
# ones, so the generated theme must match that list exactly -
# OMP_REQUIRED_TOKENS below is the schema's list for the packaged release
# (18.8.0); update it when a new omp release changes the schema. dpkg/sudo/
# apt and the omp binary are mocked and the agent directory is a scratch
# one, so nothing here touches the real system or ~/.omp.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-omp-cli / -run / -install / ohmydebn-theme-set-omp ==="

OMP_BIN=/usr/lib/ohmydebn-oh-my-pi/omp

OMP_REQUIRED_TOKENS="accent bashMode border borderAccent borderMuted customMessageBg
customMessageLabel customMessageText dim error mdCode mdCodeBlock
mdCodeBlockBorder mdHeading mdHr mdLink mdLinkUrl mdListBullet mdQuote
mdQuoteBorder muted pythonMode selectedBg statusLineBg statusLineContext
statusLineCost statusLineDirty statusLineGitClean statusLineGitDirty
statusLineModel statusLineOutput statusLinePath statusLineSep
statusLineSpend statusLineStaged statusLineSubagents statusLineUntracked
success syntaxComment syntaxFunction syntaxKeyword syntaxNumber
syntaxOperator syntaxPunctuation syntaxString syntaxType syntaxVariable
text thinkingHigh thinkingLow thinkingMedium thinkingMinimal thinkingOff
thinkingText thinkingXhigh toolDiffAdded toolDiffContext toolDiffRemoved
toolErrorBg toolOutput toolPendingBg toolSuccessBg toolTitle userMessageBg
userMessageText warning"

# setup <installed: yes|no|after-apt>
setup() {
  local installed="$1"
  mock_init
  [[ "$installed" == "yes" ]] && touch "$MOCK_DIR/installed"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn-oh-my-pi" && -f "$MOCK_DIR/installed" ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<EOF2
#!/bin/bash
mock_log "sudo \$*"
[[ "$installed" == "after-apt" && "\$*" == *"install ohmydebn-oh-my-pi"* ]] && touch "\$MOCK_DIR/installed"
exit 0
EOF2
  mock_bin omp <<'EOF2'
#!/bin/bash
mock_log "omp $* (cwd=$PWD)"
exit 0
EOF2
  for helper in ohmydebn-show-logo ohmydebn-show-done ohmydebn-ai-set-default; do
    mock_bin "$helper" <<EOF2
#!/bin/bash
mock_log "$helper \$*"
EOF2
  done
  SCRATCH_HOME=$(mktemp -d)
  for script in ohmydebn-omp-cli ohmydebn-omp-run ohmydebn-omp-install ohmydebn-theme-set-omp; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#$OMP_BIN#$MOCK_BIN/omp#g" "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
  # A current OhMyDebn theme in the Omarchy 4 semantic format (Tokyo Night).
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current/theme"
  cat >"$SCRATCH_HOME/.config/ohmydebn/current/theme/colors.toml" <<'EOF2'
accent = "#7aa2f7"
background = "#1a1b26"
foreground = "#a9b1d6"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#ad8ee6"
cyan = "#449dab"
EOF2
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  mock_cleanup
}

run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/$1" "${@:2}"
}

THEME_FILE() { echo "$SCRATCH_HOME/.omp/agent/themes/ohmydebn.json"; }

# --- installed: -cli execs the binary with its args, no install attempt ---
setup yes
run ohmydebn-omp-cli --continue "fix the bug" </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "installed: -cli execs the packaged binary with its args forwarded" "$CALLS" "omp --continue fix the bug"
assert_not_contains "installed: -cli does not run apt" "$CALLS" "sudo"
teardown

# --- installed: -run starts a fresh session dir under ~/omp-sessions ---
setup yes
run ohmydebn-omp-run </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "installed: -run execs the packaged binary" "$CALLS" "omp  (cwd=$SCRATCH_HOME/omp-sessions/session-"
assert_eq "installed: -run created exactly one session directory" "1" "$(find "$SCRATCH_HOME/omp-sessions" -mindepth 1 -maxdepth 1 -type d -name 'session-*' | wc -l)"
teardown

# --- not installed, from the menu: installs, themes and selects it, asks about the default ---
setup after-apt
printf '\n' | run ohmydebn-omp-install >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "menu install: runs apt update" "$CALLS" "sudo /usr/bin/apt update"
assert_contains "menu install: installs ohmydebn-oh-my-pi" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-oh-my-pi"
assert_eq "menu install: publishes the OhMyDebn theme" "yes" "$([[ -f "$(THEME_FILE)" ]] && echo yes || echo no)"
assert_contains "menu install: selects it for the dark slot through omp" "$CALLS" "omp config set theme.dark ohmydebn"
assert_contains "menu install: selects it for the light slot through omp" "$CALLS" "omp config set theme.light ohmydebn"
assert_contains "menu install: asks about the default AI assistant" "$CALLS" "ohmydebn-ai-set-default --ask omp"
teardown

# --- --skip-prompt: installs and themes, never asks ---
setup after-apt
run ohmydebn-omp-install --skip-prompt </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "--skip-prompt: installs" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-oh-my-pi"
assert_not_contains "--skip-prompt: never asks about the default" "$CALLS" "ohmydebn-ai-set-default"
teardown

# --- installed: -install is a no-op ---
setup yes
run ohmydebn-omp-install --skip-prompt </dev/null >/dev/null 2>&1
assert_eq "installed: -install does nothing" "" "$(cat "$MOCK_CALLS")"
assert_eq "installed: -install leaves ~/.omp alone" "no" "$([[ -e "$SCRATCH_HOME/.omp" ]] && echo yes || echo no)"
teardown

# --- theme hook: no omp agent dir means nothing is written or created ---
setup yes
run ohmydebn-theme-set-omp </dev/null >/dev/null 2>&1
assert_eq "no agent dir: creates nothing" "no" "$([[ -e "$SCRATCH_HOME/.omp" ]] && echo yes || echo no)"
teardown

# --- theme hook: exactly omp's required tokens, all resolving to real colors ---
setup yes
mkdir -p "$SCRATCH_HOME/.omp/agent"
run ohmydebn-theme-set-omp </dev/null >/dev/null 2>&1
T=$(THEME_FILE)
assert_eq "theme: colors are exactly omp's required tokens" \
  "$(tr -s ' \n' '\n' <<<"$OMP_REQUIRED_TOKENS" | sed '/^$/d' | sort)" \
  "$(jq -r '.colors | keys[]' "$T" | sort)"
assert_eq "theme: every color reference resolves to a #rrggbb var" "" \
  "$(jq -r '. as $t | .colors | to_entries[] | select(($t.vars[.value] // "") | test("^#[0-9a-fA-F]{6}$") | not) | .key' "$T")"
assert_eq "theme: every var is a #rrggbb color (the schema allows no other strings)" "" \
  "$(jq -r '.vars | to_entries[] | select(.value | test("^#[0-9a-fA-F]{6}$") | not) | .key' "$T")"
assert_eq "theme: named ohmydebn" "ohmydebn" "$(jq -r .name "$T")"
assert_eq "theme: accent comes from the theme" "#7aa2f7" "$(jq -r .vars.accent "$T")"
# Expected values computed with Omarchy's own mix_color for these inputs.
assert_eq "theme: panel = mix background foreground 6%" "#232431" "$(jq -r .vars.panel "$T")"
assert_eq "theme: mutedText = mix foreground background 34%" "#787e9a" "$(jq -r .vars.mutedText "$T")"
assert_eq "theme: without --activate, omp isn't called" "" "$(cat "$MOCK_CALLS")"
teardown

# --- theme hook: a legacy color0-15 theme falls back to its aliases ---
setup yes
mkdir -p "$SCRATCH_HOME/.omp/agent"
cat >"$SCRATCH_HOME/legacy.toml" <<'EOF2'
background = "#fafafa"
foreground = "#383a42"
color1 = "#e45649"
color2 = "#50a14f"
color3 = "#c18401"
color4 = "#4078f2"
color5 = "#a626a4"
color6 = "#0184bc"
EOF2
run ohmydebn-theme-set-omp "$SCRATCH_HOME/legacy.toml" true </dev/null >/dev/null 2>&1
T=$(THEME_FILE)
assert_eq "legacy: accent falls back to color4" "#4078f2" "$(jq -r .vars.accent "$T")"
assert_eq "legacy: success uses color2" "#50a14f" "$(jq -r '.vars[.colors.success]' "$T")"
teardown

# --- theme hook: a theme missing its core colors is skipped ---
setup yes
mkdir -p "$SCRATCH_HOME/.omp/agent"
echo 'foreground = "#ffffff"' >"$SCRATCH_HOME/broken.toml"
run ohmydebn-theme-set-omp "$SCRATCH_HOME/broken.toml" false </dev/null >/dev/null 2>&1
assert_eq "missing background: nothing published" "no" "$([[ -e "$(THEME_FILE)" ]] && echo yes || echo no)"
teardown

test_summary
