#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-set-cinnamon's cleanup of generated
# themes. Each applied theme gets a full GTK/Cinnamon theme in
# ~/.themes/ohmydebn-<name> (about 2.6 MB), and nothing removed the old
# ones - 46 folders, 122 MB, on one machine. Now applying a theme removes
# the other generated ones once Cinnamon has switched. HOME is a scratch
# directory, the template is a minimal stand-in, and gsettings is a logger.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-theme-set-cinnamon: old generated themes ==="

mock_init
H="$MOCK_DIR/home"
T="$H/.themes"
TEMPLATES="$MOCK_DIR/templates"
mkdir -p "$TEMPLATES/Gruvbox-Yellow-Dark/gtk-3.0" "$T"
printf '[Desktop Entry]\nName=Gruvbox-Yellow-Dark\n[X-GNOME-Metatheme]\nGtkTheme=Gruvbox-Yellow-Dark\n' \
  >"$TEMPLATES/Gruvbox-Yellow-Dark/index.theme"
echo "* { color: #d8a657; }" >"$TEMPLATES/Gruvbox-Yellow-Dark/gtk-3.0/gtk.css"
mkdir -p "$H/.config/ohmydebn/current"
echo "nord" >"$H/.config/ohmydebn/current/theme.name"
mock_bin gsettings <<'STUB'
#!/bin/bash
mock_log "gsettings $*"
STUB

# Left behind by earlier switches, plus things that aren't OhMyDebn's to remove.
for old in ohmydebn-gruvbox ohmydebn-a-aerial-view-of-a-snowy-mountain-palette ohmydebn-gruvbox-hdpi; do
  mkdir -p "$T/$old"
done
mkdir -p "$T/My-Own-Theme" "$MOCK_DIR/dev-theme"
ln -s "$MOCK_DIR/dev-theme" "$T/ohmydebn-dev-link"

sed "s#/usr/share/ohmydebn-templates#$TEMPLATES#g" "$REPO_ROOT/bin/ohmydebn-theme-set-cinnamon" >"$MOCK_DIR/hook"
HOME="$H" PATH="$(mock_path)" bash "$MOCK_DIR/hook" nord "$REPO_ROOT/themes/ohmydebn/colors.toml" false </dev/null >/dev/null 2>&1
STATUS=$?

assert_eq "applies: exits 0" "0" "$STATUS"
assert_contains "applies: Cinnamon is switched to the new theme" "$(cat "$MOCK_CALLS")" "gsettings set org.cinnamon.theme name ohmydebn-nord"
assert_eq "the new theme is generated" "yes" "$([ -f "$T/ohmydebn-nord/index.theme" ] && echo yes || echo no)"
for old in ohmydebn-gruvbox ohmydebn-a-aerial-view-of-a-snowy-mountain-palette ohmydebn-gruvbox-hdpi; do
  assert_eq "an older generated theme is removed: $old" "no" "$([ -e "$T/$old" ] && echo yes || echo no)"
done
assert_eq "a theme of the user's own is kept" "yes" "$([ -d "$T/My-Own-Theme" ] && echo yes || echo no)"
assert_eq "a symlinked theme is kept" "yes" "$([ -L "$T/ohmydebn-dev-link" ] && echo yes || echo no)"
assert_eq "...and so is what it points to" "yes" "$([ -d "$MOCK_DIR/dev-theme" ] && echo yes || echo no)"
mock_cleanup

test_summary
