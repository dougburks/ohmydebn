#!/bin/bash
#
# Unit tests for T3 Code: bin/ohmydebn-t3code (install on demand, then open
# through the package's own launcher, which puts OhMyDebn's agent CLIs on
# PATH under the names T3 Code looks for), bin/ohmydebn-t3code-install
# (installs, creates T3 Code's state directory and selects the OhMyDebn
# theme), and bin/ohmydebn-theme-set-t3code (publishes the current theme as
# a T3 Code environment theme - a port of Omarchy's t3code.json.tpl).
# dpkg/sudo/apt and the launcher are mocked and T3CODE_HOME points at a
# scratch directory, so nothing here touches the real system or ~/.t3.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-t3code / ohmydebn-t3code-install / ohmydebn-theme-set-t3code ==="

LAUNCHER=/usr/lib/ohmydebn-t3code/ohmydebn-t3code-launch

# setup <installed: yes|no|after-apt>
setup() {
  local installed="$1"
  mock_init
  [[ "$installed" == "yes" ]] && touch "$MOCK_DIR/installed"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && "$2" == "ohmydebn-t3code" && -f "$MOCK_DIR/installed" ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$*" == *"install ohmydebn-t3code"* ]] && touch "$MOCK_DIR/installed"
exit 0
EOF2
  mock_bin t3code-launch <<'EOF2'
#!/bin/bash
mock_log "launch $*"
EOF2
  mock_bin ohmydebn-launch-floating-terminal-with-presentation <<'EOF2'
#!/bin/bash
mock_log "presentation $1"
"$2"
EOF2
  mock_bin ohmydebn-ai-set-default <<'EOF2'
#!/bin/bash
mock_log "ai-set-default $*"
EOF2
  SCRATCH_HOME=$(mktemp -d)
  export T3CODE_HOME="$SCRATCH_HOME/.t3"
  for script in ohmydebn-t3code ohmydebn-t3code-install ohmydebn-theme-set-t3code; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#$LAUNCHER#$MOCK_BIN/t3code-launch#g" "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
  # A current OhMyDebn theme in the Omarchy 4 semantic format (Tokyo Night).
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current/theme"
  cat >"$SCRATCH_HOME/.config/ohmydebn/current/theme/colors.toml" <<'EOF2'
mode = "dark"
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"
background = "#1a1b26"
dark_background = "#13141c"
foreground = "#a9b1d6"
dark_foreground = "#565f89"
bright_foreground = "#c0caf5"
red = "#f7768e"
yellow = "#e0af68"
color8 = "#414868"
EOF2
}

teardown() {
  rm -rf "$SCRATCH_HOME"
  unset T3CODE_HOME
  mock_cleanup
}

run() {
  HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/$1" "${@:2}"
}

THEME_FILE() { echo "$T3CODE_HOME/userdata/themes/ohmydebn.json"; }
SETTINGS_FILE() { echo "$T3CODE_HOME/userdata/settings.json"; }

# --- installed: the launcher opens it through the package's PATH-shim launcher ---
setup yes
run ohmydebn-t3code >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "installed: opens through the package's launcher" "$CALLS" "launch"
assert_not_contains "installed: no install attempt" "$CALLS" "sudo"
teardown

# --- not installed: installs in the presentation window, then opens ---
setup no
run ohmydebn-t3code < <(printf '\n\n') >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "not installed: installs in a 'T3 Code' presentation window" "$CALLS" "presentation T3 Code"
assert_contains "not installed: runs apt update" "$CALLS" "sudo /usr/bin/apt update"
assert_contains "not installed: installs ohmydebn-t3code" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-t3code"
assert_contains "not installed: asks about the default AI assistant" "$CALLS" "ai-set-default --ask t3code"
assert_contains "not installed: opens it once installed" "$CALLS" "launch"
assert_eq "not installed: creates T3 Code's state dir and publishes the theme" "yes" "$([[ -f "$(THEME_FILE)" ]] && echo yes || echo no)"
assert_eq "not installed: selects the OhMyDebn theme" "ohmydebn" "$(jq -r .defaultTheme "$(SETTINGS_FILE)")"
teardown

# --- --skip-prompt: installs and themes, never asks about the default ---
setup no
run ohmydebn-t3code-install --skip-prompt </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "--skip-prompt: installs" "$CALLS" "sudo /usr/bin/apt -y install ohmydebn-t3code"
assert_not_contains "--skip-prompt: never asks about the default" "$CALLS" "ai-set-default"
assert_eq "--skip-prompt: still selects the OhMyDebn theme" "ohmydebn" "$(jq -r .defaultTheme "$(SETTINGS_FILE)")"
teardown

# --- installed: -install is a no-op ---
setup yes
run ohmydebn-t3code-install --skip-prompt >/dev/null 2>&1
assert_eq "installed: -install does nothing" "" "$(cat "$MOCK_CALLS")"
assert_eq "installed: -install leaves ~/.t3 alone" "no" "$([[ -e "$T3CODE_HOME" ]] && echo yes || echo no)"
teardown

# --- theme hook: no T3 Code state dir means nothing is written or created ---
setup yes
run ohmydebn-theme-set-t3code >/dev/null 2>&1
assert_eq "no state dir: exits cleanly" "0" "$?"
assert_eq "no state dir: creates nothing" "no" "$([[ -e "$T3CODE_HOME" ]] && echo yes || echo no)"
teardown

# --- theme hook: semantic theme -> Omarchy's palette, same mix math ---
setup yes
mkdir -p "$T3CODE_HOME/userdata"
run ohmydebn-theme-set-t3code >/dev/null 2>&1
T=$(THEME_FILE)
assert_eq "semantic: appearance from mode" "dark" "$(jq -r .appearance "$T")"
assert_eq "semantic: canvas is the background" "#1a1b26" "$(jq -r .canvas "$T")"
assert_eq "semantic: accent" "#7aa2f7" "$(jq -r .accent "$T")"
assert_eq "semantic: sidebar is dark_background" "#13141c" "$(jq -r .colors.sidebar "$T")"
# Expected values computed with Omarchy's own mix_color for these inputs.
assert_eq "semantic: sidebarRowHover = mix dark_background foreground 6%" "#1c1d27" "$(jq -r .colors.sidebarRowHover "$T")"
assert_eq "semantic: sidebarRowActive = mix dark_background accent 18%" "#262e43" "$(jq -r .colors.sidebarRowActive "$T")"
assert_eq "semantic: error = mix red foreground 35%" "#dc8ba7" "$(jq -r .colors.error "$T")"
assert_eq "semantic: warning = mix yellow foreground 35%" "#cdb08f" "$(jq -r .colors.warning "$T")"
assert_eq "semantic: no temp files left behind" "ohmydebn.json" "$(ls "$T3CODE_HOME/userdata/themes")"
assert_eq "semantic: without --activate, settings.json is untouched" "no" "$([[ -e "$(SETTINGS_FILE)" ]] && echo yes || echo no)"
teardown

# --- theme hook: legacy color0-15 theme in light mode falls back correctly ---
setup yes
mkdir -p "$T3CODE_HOME/userdata"
cat >"$SCRATCH_HOME/legacy.toml" <<'EOF2'
background = "#fafafa"
foreground = "#383a42"
accent = "#4078f2"
selection_background = "#e5e5e6"
color1 = "#e45649"
color3 = "#c18401"
color8 = "#a0a1a7"
color15 = "#090a0b"
EOF2
run ohmydebn-theme-set-t3code "$SCRATCH_HOME/legacy.toml" true >/dev/null 2>&1
T=$(THEME_FILE)
assert_eq "legacy: appearance from the light-mode argument" "light" "$(jq -r .appearance "$T")"
assert_eq "legacy: sidebar falls back to background" "#fafafa" "$(jq -r .colors.sidebar "$T")"
assert_eq "legacy: border falls back to color8" "#a0a1a7" "$(jq -r .colors.border "$T")"
assert_eq "legacy: selection falls back to selection_background" "#e5e5e6" "$(jq -r .colors.sidebarRowSelected "$T")"
assert_eq "legacy: cursor falls back to color15" "#090a0b" "$(jq -r .colors.terminalCursor "$T")"
teardown

# --- theme hook: a theme missing its core colors is skipped, not published broken ---
setup yes
mkdir -p "$T3CODE_HOME/userdata"
echo 'foreground = "#ffffff"' >"$SCRATCH_HOME/broken.toml"
run ohmydebn-theme-set-t3code "$SCRATCH_HOME/broken.toml" false >/dev/null 2>&1
assert_eq "missing background: nothing published" "no" "$([[ -e "$(THEME_FILE)" ]] && echo yes || echo no)"
teardown

# --- --activate: sets only the two theme keys, keeps everything else ---
setup yes
mkdir -p "$T3CODE_HOME/userdata"
echo '{"providerInstances":{"opencode":{"driver":"opencode","config":{"binaryPath":"opencode-cli"}}},"defaultTheme":"nightfall"}' >"$(SETTINGS_FILE)"
run ohmydebn-theme-set-t3code --activate >/dev/null 2>&1
S=$(SETTINGS_FILE)
assert_eq "--activate: selects the OhMyDebn theme" "ohmydebn" "$(jq -r .defaultTheme "$S")"
assert_contains "--activate: stamps defaultThemeSetAt" "$(jq -r .defaultThemeSetAt "$S")" "T"
assert_eq "--activate: keeps unrelated settings" "opencode-cli" "$(jq -r .providerInstances.opencode.config.binaryPath "$S")"
teardown

# --- --activate: an unreadable settings.json is left exactly as it was ---
setup yes
mkdir -p "$T3CODE_HOME/userdata"
echo 'not json' >"$(SETTINGS_FILE)"
run ohmydebn-theme-set-t3code --activate >/dev/null 2>&1
assert_eq "invalid settings.json: left untouched" "not json" "$(cat "$(SETTINGS_FILE)")"
assert_eq "invalid settings.json: no temp files left behind" "settings.json themes" "$(ls "$T3CODE_HOME/userdata" | tr '\n' ' ' | sed 's/ $//')"
teardown

test_summary
