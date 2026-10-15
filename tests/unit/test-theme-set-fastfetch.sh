#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-fastfetch: the themed logo it
# writes (further down), and its SIGUSR2 refresh of an already-open
# ohmydebn-fastfetch-gui window (bin/ohmydebn-fastfetch-pause).
# `kill` is a bash builtin, so it can't be mocked via PATH like pkill is for
# btop/cava - these spawn a real short-lived background process and check
# whether it actually received SIGUSR2, rather than mocking the signal send.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-theme-set-fastfetch"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-fastfetch ==="

run_theme_set_fastfetch() {
  local scratch_home="$1"
  HOME="$scratch_home" bash "$SCRIPT" >/dev/null 2>&1
}

# Scenario 1: a live process whose cmdline contains "ohmydebn-fastfetch-pause"
# (standing in for the real process) gets signaled.
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.cache/ohmydebn"
RECEIVED_FILE="$MOCK_DIR/received"
: >"$RECEIVED_FILE"
FAKE_SCRIPT="$MOCK_BIN/ohmydebn-fastfetch-pause"
cat >"$FAKE_SCRIPT" <<EOF
#!/bin/bash
# "sleep & wait", not a bare sleep or read -t: bash only runs a pending
# trap promptly while blocked in a builtin wait, so a backgrounded sleep
# reaped via \`wait\` is the standard interruptible-sleep idiom. A bare
# external sleep defers the trap until it exits on its own. read -t would
# work too in the real ohmydebn-fastfetch-pause (which always runs under a
# real pty) but returns instantly on EOF here, since this test has no
# controlling tty for the backgrounded process to read from.
trap 'echo signaled >>"$RECEIVED_FILE"' USR2
sleep 5 &
wait \$!
EOF
chmod +x "$FAKE_SCRIPT"
"$FAKE_SCRIPT" &
FAKE_PID=$!
echo "$FAKE_PID" >"$SCRATCH_HOME/.cache/ohmydebn/fastfetch-pause.pid"
# Give the background process time to reach its own trap line - signaling
# before that registers would hit SIGUSR2's default action (terminate)
# instead, since no handler is registered yet.
sleep 0.3
run_theme_set_fastfetch "$SCRATCH_HOME"
sleep 0.3
assert_contains "live matching process: SIGUSR2 delivered" "$(cat "$RECEIVED_FILE")" "signaled"
kill "$FAKE_PID" 2>/dev/null
wait "$FAKE_PID" 2>/dev/null
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: a stale pidfile pointing at a live PID that ISN'T
# ohmydebn-fastfetch-pause (e.g. reused by an unrelated process since) must
# not be signaled - use this test script's own PID as the foreign process.
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.cache/ohmydebn"
RECEIVED=""
trap 'RECEIVED=1' USR2
echo "$$" >"$SCRATCH_HOME/.cache/ohmydebn/fastfetch-pause.pid"
run_theme_set_fastfetch "$SCRATCH_HOME"
sleep 0.3
assert_eq "stale pidfile (foreign process): SIGUSR2 not sent" "" "$RECEIVED"
trap - USR2
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: no pidfile at all (fastfetch window never opened this session)
# - script must not error out.
mock_init
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.cache/ohmydebn"
HOME="$SCRATCH_HOME" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "no pidfile: script exits cleanly" "0" "$?"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# --- The logo: config/fastfetch/logo.txt in the theme's logo gradient,
# written to ~/.config/fastfetch/ohmydebn-logo.txt. The real
# ohmydebn-theme-logo-colors supplies the gradient. The color checks use a
# small fixture logo whose corners are drawn, so its first cell is exactly
# the gradient's start, its last exactly the end, and its top-right corner
# exactly halfway.
mock_init
sed -e "s#/usr/share/ohmydebn/bin#$REPO_ROOT/bin#g" \
  -e "s#/usr/share/ohmydebn/config#$REPO_ROOT/config#g" "$SCRIPT" >"$MOCK_DIR/hook.sh"
printf '█  █\n▀  ▄\n' >"$MOCK_DIR/logo.txt"
sed "s#^LOGO_SOURCE=.*#LOGO_SOURCE=$MOCK_DIR/logo.txt#" "$MOCK_DIR/hook.sh" >"$MOCK_DIR/hook-fixture.sh"
LOGO_SOURCE="$REPO_ROOT/config/fastfetch/logo.txt"

run_logo_hook() {
  HOME="$SCRATCH_HOME" bash "$MOCK_DIR/${1:-hook}.sh" </dev/null >"$MOCK_DIR/out" 2>&1
}
strip_colors() {
  sed $'s/\e\\[[0-9;]*m//g' "$1"
}
# The fixture logo with every color written out, escape characters shown.
fixture_colors() {
  sed $'s/\e/ESC/g' "$1"
}
write_theme() {
  mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current/theme"
  printf 'accent = "#%s"\nbackground = "#1a1b26"\nblue = "#%s"\ncyan = "#%s"\n' "$@" \
    >"$SCRATCH_HOME/.config/ohmydebn/current/theme/colors.toml"
}

# Scenario 4: a theme, with the real logo - it keeps its exact shape, each
# line ends with a color reset, and the file is readable by all.
SCRATCH_HOME=$(mktemp -d)
LOGO="$SCRATCH_HOME/.config/fastfetch/ohmydebn-logo.txt"
write_theme 7aa2f7 7aa2f7 449dab
run_logo_hook
assert_eq "theme: hook succeeds" "0" "$?"
assert_eq "theme: the logo keeps its shape" "$(cat "$LOGO_SOURCE")" "$(strip_colors "$LOGO")"
assert_eq "theme: every line ends with a color reset" "$(wc -l <"$LOGO_SOURCE")" \
  "$(grep -c $'\e\\[0m$' "$LOGO")"
assert_eq "theme: logo is world-readable, not writable" "644" "$(stat -c %a "$LOGO")"

# Scenario 5: run again with nothing changed - the file isn't rewritten.
touch -d '2020-01-01' "$LOGO"
BEFORE=$(stat -c %Y "$LOGO")
run_logo_hook
assert_eq "unchanged colors: logo not rewritten" "$BEFORE" "$(stat -c %Y "$LOGO")"
rm -rf "$SCRATCH_HOME"

# Scenario 6: the gradient runs from the accent (top left) to cyan (bottom
# right), corner to corner, and blank cells get no color.
SCRATCH_HOME=$(mktemp -d)
LOGO="$SCRATCH_HOME/.config/fastfetch/ohmydebn-logo.txt"
write_theme 7aa2f7 7aa2f7 449dab
run_logo_hook hook-fixture
assert_eq "gradient: accent to cyan, corner to corner" \
  "ESC[38;2;122;162;247m█  ESC[38;2;95;160;209m█ESC[0m
ESC[38;2;95;160;209m▀  ESC[38;2;68;157;171m▄ESC[0m" "$(fixture_colors "$LOGO")"

# Scenario 7: a theme change recolors it, leaving no temporary files.
write_theme d14d41 205ea6 3aa99f
run_logo_hook hook-fixture
assert_eq "new theme: recolored, accent to cyan via blue" \
  "ESC[38;2;209;77;65m█  ESC[38;2;32;94;166m█ESC[0m
ESC[38;2;32;94;166m▀  ESC[38;2;58;169;159m▄ESC[0m" "$(fixture_colors "$LOGO")"
ls -A "$SCRATCH_HOME/.config/fastfetch" >"$MOCK_DIR/ls"
assert_not_contains "no temporary files left behind" "$(cat "$MOCK_DIR/ls")" "ohmydebn-logo.txt."
rm -rf "$SCRATCH_HOME"

# Scenario 8: no theme at all - the default palette (488bff b2e7de 57eaf7).
SCRATCH_HOME=$(mktemp -d)
LOGO="$SCRATCH_HOME/.config/fastfetch/ohmydebn-logo.txt"
run_logo_hook hook-fixture
assert_eq "no theme: hook succeeds" "0" "$?"
assert_eq "no theme: the default palette" \
  "ESC[38;2;72;139;255m█  ESC[38;2;178;231;222m█ESC[0m
ESC[38;2;178;231;222m▀  ESC[38;2;87;234;247m▄ESC[0m" "$(fixture_colors "$LOGO")"
rm -rf "$SCRATCH_HOME"

# Scenario 9: both fastfetch configs point at the colored logo, printed
# as-is, and the shape file fits beside fastfetch's info lines (18 rows,
# at most 36 columns).
for config in config.jsonc.tpl config-default.jsonc; do
  assert_contains "$config: raw logo from the colored copy" \
    "$(tr -d ' \n' <"$REPO_ROOT/config/fastfetch/$config")" \
    '"logo":{"type":"file-raw","source":"~/.config/fastfetch/ohmydebn-logo.txt"}'
done
assert_eq "logo.txt: 18 rows" "18" "$(wc -l <"$LOGO_SOURCE")"
assert_eq "logo.txt: at most 36 columns" "yes" "$(LC_ALL=C.UTF-8 bash -c '
  w=0; while IFS= read -r l; do [ ${#l} -gt $w ] && w=${#l}; done <"$1"; [ $w -le 36 ] && [ $w -gt 30 ] && echo yes' _ "$LOGO_SOURCE")"
mock_cleanup

test_summary
