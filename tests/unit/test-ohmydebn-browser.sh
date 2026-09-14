#!/bin/bash
#
# Unit tests for bin/ohmydebn-browser (Super+B's target). It must prefer
# the desktop-wide default browser - resolved via xdg-settings, its
# .desktop file's Exec= line parsed and exec'd directly (no gtk-launch:
# GIO/D-Bus activation detaches the browser from the launcher's process
# tree, which threw off automatic tiling) - then fall back through
# x-www-browser and sensible-browser, and finally fail loudly rather than
# silently doing nothing the way the old hardcoded gnome-www-browser
# target did once that alternative went unset.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BROWSER_SCRIPT="$REPO_ROOT/bin/ohmydebn-browser"
BASH_BIN="$(command -v bash)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-browser ==="

mock_init

# A fake XDG data dir for .desktop files, pointed at via XDG_DATA_HOME
# below; XDG_DATA_DIRS is aimed at an empty dir so the real system's
# /usr/share/applications can't leak into the lookup.
MOCK_DATA="$MOCK_DIR/data"
MOCK_DATA_EMPTY="$MOCK_DIR/data-empty"
mkdir -p "$MOCK_DATA/applications" "$MOCK_DATA_EMPTY"

# Isolated PATH (no real system PATH) so tests are deterministic regardless
# of what's actually installed on the machine running them. bash itself is
# invoked by absolute path so the restricted PATH only affects the script's
# own `command -v` lookups, not finding bash itself.
run_browser() {
  : >"$MOCK_CALLS"
  PATH="$MOCK_BIN" XDG_DATA_HOME="$MOCK_DATA" XDG_DATA_DIRS="$MOCK_DATA_EMPTY" \
    "$BASH_BIN" "$BROWSER_SCRIPT" >"$MOCK_DIR/out" 2>&1
  echo $?
}

# --- default browser resolvable: its Exec binary is exec'd directly, field codes stripped ---
mock_bin xdg-settings <<'EOF'
#!/bin/bash
echo "mockbrowser.desktop"
EOF
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Name=Mock Browser
Exec=mockbrowser --new-window %U
Type=Application

[Desktop Action new-private-window]
Name=Private Window
Exec=mockbrowser --private %U
EOF
mock_bin mockbrowser <<'EOF'
#!/bin/bash
echo "mockbrowser $*" >>"$MOCK_CALLS"
EOF
mock_bin x-www-browser <<'EOF'
#!/bin/bash
echo "x-www-browser $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_eq "default browser path: exits 0" "0" "$status"
assert_eq "default browser path: execs Exec binary, args kept, %U stripped" "mockbrowser --new-window" "$(cat "$MOCK_CALLS")"
assert_not_contains "default browser path: main Exec used, not a Desktop Action's" "$(cat "$MOCK_CALLS")" "--private"
assert_not_contains "default browser path: does not fall back to x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- flatpak-style Exec line: file-forwarding @@u %u @@ markers all stripped ---
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=mockbrowser run --command=firefox @@u %u @@
EOF
status=$(run_browser)
assert_eq "flatpak-style Exec: @@u/%u/@@ markers stripped" "mockbrowser run --command=firefox" "$(cat "$MOCK_CALLS")"

# --- quoted Exec argument containing a space survives word splitting ---
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=mockbrowser --class "Mock Browser" %u
EOF
status=$(run_browser)
assert_eq "quoted Exec arg: passed as one argument" "mockbrowser --class Mock Browser" "$(cat "$MOCK_CALLS")"

# --- webapp-style Exec with unquoted '&' in the URL: literal, not a parse error ---
# Regression guard: the old eval-based split died on '&' as a shell syntax
# error, silently falling back to x-www-browser despite a valid default.
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=mockbrowser --app=https://site/?a=1&b=2 %u
EOF
status=$(run_browser)
assert_eq "unquoted & in Exec URL: passed through literally" "mockbrowser --app=https://site/?a=1&b=2" "$(cat "$MOCK_CALLS")"

# --- $(...) and $VAR in Exec are literal text, never evaluated ---
# Regression guard for the eval this parser replaced: a crafted Exec=
# line could execute arbitrary commands at parse time. The XDG spec (and
# gtk-launch) treat these as plain characters.
mock_bin evilcmd <<'EOF'
#!/bin/bash
echo "evilcmd RAN" >>"$MOCK_CALLS"
EOF
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=mockbrowser "note $(evilcmd) $HOME" %u
EOF
status=$(run_browser)
assert_not_contains "Exec \$(...) is never executed" "$(cat "$MOCK_CALLS")" "evilcmd RAN"
assert_contains "Exec \$(...)/\$VAR arrive as literal argument text" "$(cat "$MOCK_CALLS")" 'mockbrowser note $(evilcmd) $HOME'

# --- final Exec line with no trailing newline still parses ---
# Regression guard: plain `while read` drops a last line that isn't
# newline-terminated, losing the Exec= entirely.
printf '[Desktop Entry]\nExec=mockbrowser --new-window %%u' >"$MOCK_DATA/applications/mockbrowser.desktop"
status=$(run_browser)
assert_eq "no trailing newline: Exec still parsed" "mockbrowser --new-window" "$(cat "$MOCK_CALLS")"

# --- CRLF-terminated .desktop file still parses ---
printf '[Desktop Entry]\r\nExec=mockbrowser --new-window %%u\r\n' >"$MOCK_DATA/applications/mockbrowser.desktop"
status=$(run_browser)
assert_eq "CRLF line endings: Exec still parsed" "mockbrowser --new-window" "$(cat "$MOCK_CALLS")"

# --- embedded field codes and %% escapes inside larger arguments ---
# %% is the spec's escape for a literal %; an embedded %u expands to
# nothing since we launch with no URL - matching GIO's expansion and
# ohmydebn-menu-picker's _strip_exec_field_codes.
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=mockbrowser --homepage=%u --zoom=100%% %U
EOF
status=$(run_browser)
assert_eq "embedded %u drops, %% becomes literal %" "mockbrowser --homepage= --zoom=100%" "$(cat "$MOCK_CALLS")"

# --- unterminated quote in Exec: graceful fallback, not a hang or crash ---
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=mockbrowser "unterminated
EOF
status=$(run_browser)
assert_contains "malformed Exec quoting: falls back to x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- Exec binary resolves but exec itself fails: fallback chain still runs ---
# Regression guard: without `shopt -s execfail`, bash terminates the
# script on a failed exec (wrong-arch binary, missing loader) and the
# fallback chain below it was unreachable - Super+B silently did nothing.
printf '\177ELF\0not really a binary\n' >"$MOCK_BIN/brokenbrowser"
chmod +x "$MOCK_BIN/brokenbrowser"
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=brokenbrowser %u
EOF
status=$(run_browser)
assert_eq "unexecutable Exec binary: exits 0 via fallback" "0" "$status"
assert_contains "unexecutable Exec binary: falls back to x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# Restore the good mock .desktop for the sections below.
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=mockbrowser --new-window %U
EOF

# --- xdg-settings returns empty (no default set): falls back to x-www-browser ---
mock_bin xdg-settings <<'EOF'
#!/bin/bash
echo ""
EOF
status=$(run_browser)
assert_contains "empty xdg-settings result: falls back to x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- stale/uninstalled desktop id (no .desktop file found): falls back ---
mock_bin xdg-settings <<'EOF'
#!/bin/bash
echo "stale-browser.desktop"
EOF
status=$(run_browser)
assert_contains "missing .desktop file: falls back to x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- .desktop file exists but its Exec binary isn't installed: falls back ---
mock_bin xdg-settings <<'EOF'
#!/bin/bash
echo "mockbrowser.desktop"
EOF
cat >"$MOCK_DATA/applications/mockbrowser.desktop" <<'EOF'
[Desktop Entry]
Exec=not-actually-installed %u
EOF
status=$(run_browser)
assert_contains "Exec binary missing: falls back to x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- xdg-settings missing entirely: goes straight to x-www-browser ---
rm -f "$MOCK_BIN/xdg-settings"
status=$(run_browser)
assert_contains "no xdg tooling: uses x-www-browser" "$(cat "$MOCK_CALLS")" "x-www-browser"

# --- Only sensible-browser available: used as last resort ---
rm -f "$MOCK_BIN/x-www-browser"
mock_bin sensible-browser <<'EOF'
#!/bin/bash
echo "sensible-browser $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_contains "only sensible-browser available: used" "$(cat "$MOCK_CALLS")" "sensible-browser"

# --- Nothing available at all: fails with a notification instead of silently doing nothing ---
rm -f "$MOCK_BIN/sensible-browser"
mock_bin notify-send <<'EOF'
#!/bin/bash
echo "notify-send $*" >>"$MOCK_CALLS"
EOF
status=$(run_browser)
assert_eq "nothing available: exits non-zero" "1" "$status"
assert_contains "nothing available: notifies the user" "$(cat "$MOCK_CALLS")" "notify-send"

mock_cleanup
test_summary
