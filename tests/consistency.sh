#!/bin/bash
#
# consistency.sh: Static, no-infrastructure repo self-consistency checks.
# Everything here just reads files in this repo - no mocking, no real apt
# queries, no VM. Each check is aimed at a mistake actually made (or
# narrowly avoided) during development: a stale rename reference, a
# forgotten chmod +x, an automation flag a target script didn't support
# yet, a file created but never wired into its all.sh, package names
# drifting out of sync across the three places they're now split across,
# a one-time state marker reused by two features, a config guard checking
# a package name that doesn't match anything real, a menu case arm that
# can never match its own menu, two features silently fighting over
# the same keybinding, and the flattened Search menu silently losing sync
# with the real nested menu tree it's generated from.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # consumed by the functions in extract-packages.sh, sourced below
DEPENDENCIES_SH="$REPO_ROOT/install/packaging/dependencies.sh"
POWER_USER_SH="$REPO_ROOT/install/packaging/power-user.sh"
# shellcheck disable=SC2034
REMOVE_ALL_SH="$REPO_ROOT/bin/ohmydebn-pkg-remove-all-optional"
# shellcheck disable=SC2034
BUILD_SCRIPT="$HOME/git/ohmydebn-package-build/build-package-ohmydebn.sh"

source "$REPO_ROOT/tests/lib/extract-packages.sh"
source "$REPO_ROOT/bin/ohmydebn-menu-tree"

FAIL=0

echo "=== consistency ==="

# -- check 1: every /usr/share/ohmydebn/bin/X reference resolves to a real file --

echo
echo "-- bin/ script references resolve --"
CHECKED=0
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  CHECKED=$((CHECKED + 1))
  if [[ ! -f "$REPO_ROOT/bin/$name" ]]; then
    echo "  FAIL - referenced as /usr/share/ohmydebn/bin/$name but bin/$name doesn't exist"
    FAIL=$((FAIL + 1))
  fi
done < <(grep -rhoE '/usr/share/ohmydebn/bin/[^ "'"'"'`;)]+' "$REPO_ROOT/bin" "$REPO_ROOT/install" 2>/dev/null |
  sed 's#.*/bin/##' | grep -v '\$' | sort -u)
echo "  checked $CHECKED unique references"

# -- check 2: every bin/* and install/**/*.sh file is executable --

echo
echo "-- executable bits --"
CHECKED=0
while IFS= read -r f; do
  CHECKED=$((CHECKED + 1))
  if [[ ! -x "$f" ]]; then
    echo "  FAIL - not executable: ${f#"$REPO_ROOT"/}"
    FAIL=$((FAIL + 1))
  fi
done < <(find "$REPO_ROOT/bin" -type f; find "$REPO_ROOT/install" -type f -name "*.sh")
echo "  checked $CHECKED files"

# -- check 3: every script invoked with --skip-prompt actually supports it --
#
# power-user.sh and ohmydebn-pkg-remove-all-optional are currently the only
# automation that relies on --skip-prompt. If a future file adds more of
# these calls, extend the extraction below to match.

echo
echo "-- --skip-prompt consistency (install/packaging/power-user.sh, bin/ohmydebn-pkg-remove-all-optional) --"
SKIP_PROMPT_NAMES=()
mapfile -t LOOP_NAMES < <(sed -n '/^  for SCRIPT in/,/; do/{p; /; do/q}' "$POWER_USER_SH" |
  sed '1s/^  for SCRIPT in //; s/; do$//; s/\\$//' | tr -s ' \t' '\n' | grep -v '^\s*$')
SKIP_PROMPT_NAMES+=("${LOOP_NAMES[@]}")
if grep -q 'ohmydebn-pkg-remove-all-optional --skip-prompt' "$POWER_USER_SH"; then
  SKIP_PROMPT_NAMES+=("ohmydebn-pkg-remove-all-optional")
fi
# ohmydebn-pkg-remove-all-optional's own second `for PACKAGE in` loop (the
# first is the plain apt-purge glob list) re-invokes each app's dedicated
# ohmydebn-<package>-remove script with --skip-prompt, since the user
# already confirmed once at this script's own top-level prompt.
mapfile -t REMOVE_ALL_PACKAGES < <(awk '/^for PACKAGE in/{n++} n==2{print; if (/; do$/) exit}' "$REMOVE_ALL_SH" |
  sed '1s/^for PACKAGE in //; s/; do$//; s/\\$//' | tr -s ' \t' '\n' | grep -v '^\s*$')
for pkg in "${REMOVE_ALL_PACKAGES[@]}"; do
  SKIP_PROMPT_NAMES+=("ohmydebn-${pkg}-remove")
done
# Pi sits just outside that loop (its dpkg package name,
# ohmydebn-pi-coding-agent, isn't the same string as its remove script's
# ohmydebn-pi-remove, unlike every other entry the loop above handles) -
# same explicit-grep exception already used above for
# ohmydebn-pkg-remove-all-optional's own --skip-prompt invocation.
if grep -q 'ohmydebn-pi-remove --skip-prompt' "$REMOVE_ALL_SH"; then
  SKIP_PROMPT_NAMES+=("ohmydebn-pi-remove")
fi
CHECKED=0
for name in "${SKIP_PROMPT_NAMES[@]}"; do
  CHECKED=$((CHECKED + 1))
  if [[ ! -f "$REPO_ROOT/bin/$name" ]]; then
    echo "  FAIL - '$name' is invoked with --skip-prompt but bin/$name doesn't exist"
    FAIL=$((FAIL + 1))
  elif ! grep -q -- '--skip-prompt' "$REPO_ROOT/bin/$name"; then
    echo "  FAIL - '$name' is invoked with --skip-prompt but doesn't handle that flag"
    FAIL=$((FAIL + 1))
  fi
done
echo "  checked $CHECKED scripts"

# -- check 4: every packaging/config/cleanup/finalization file is sourced from its all.sh --

echo
echo "-- files wired into their all.sh --"
CHECKED=0
for dir in packaging config cleanup finalization; do
  ALL_SH="$REPO_ROOT/install/$dir/all.sh"
  [[ -f "$ALL_SH" ]] || continue
  for f in "$REPO_ROOT/install/$dir"/*.sh; do
    name=$(basename "$f")
    [[ "$name" == "all.sh" ]] && continue
    CHECKED=$((CHECKED + 1))
    if ! grep -q "$dir/$name" "$ALL_SH"; then
      echo "  FAIL - install/$dir/$name exists but isn't sourced from install/$dir/all.sh"
      FAIL=$((FAIL + 1))
    fi
  done
done
echo "  checked $CHECKED files across 4 phase directories"

# -- check 5: no package name duplicated within or across dependencies.sh / --
#             power-user.sh / build-package-ohmydebn.sh's Category A

echo
echo "-- no duplicate/orphaned packages across the three package lists --"
for entry in "dependencies.sh:extract_dependencies_sh_packages" \
  "power-user.sh:extract_power_user_sh_packages" \
  "build-package-ohmydebn.sh:extract_fpm_hard_depends"; do
  label="${entry%%:*}"
  fn="${entry#*:}"
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    echo "  FAIL - '$pkg' is listed more than once within $label itself"
    FAIL=$((FAIL + 1))
  done < <("$fn" | sort | uniq -d)
done

ALL_PKGS=$( (extract_dependencies_sh_packages
  extract_power_user_sh_packages
  extract_fpm_hard_depends) )
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue
  echo "  FAIL - '$pkg' appears in more than one of {dependencies.sh, power-user.sh, build-package-ohmydebn.sh}"
  FAIL=$((FAIL + 1))
done < <(echo "$ALL_PKGS" | sort | uniq -d)
echo "  checked $(echo "$ALL_PKGS" | grep -c .) package entries across all three lists"

# -- check 6: no two files share the same one-time state-file marker --

echo
echo "-- state-file marker collisions --"
# shellcheck disable=SC2088 # deliberately literal - matching the literal
# unexpanded "~/..." text as it appears written in other scripts' source,
# not a path for this shell to expand.
mapfile -t MARKERS < <(grep -rhoE '~/\.local/state/ohmydebn-config/[a-zA-Z0-9_.-]+' \
  "$REPO_ROOT/install" "$REPO_ROOT/bin" 2>/dev/null | sort -u)
for marker in "${MARKERS[@]}"; do
  mapfile -t USING_FILES < <(grep -rl -F "$marker" "$REPO_ROOT/install" "$REPO_ROOT/bin" 2>/dev/null | sort -u)
  if [[ "${#USING_FILES[@]}" -gt 1 ]]; then
    echo "  FAIL - marker '$marker' is used by more than one file: ${USING_FILES[*]#"$REPO_ROOT"/}"
    FAIL=$((FAIL + 1))
  fi
done
echo "  checked ${#MARKERS[@]} unique markers"

# -- check 7: install/config/*.sh guard package names are real, known packages --

echo
echo "-- config-guard package names match known packages --"
mapfile -t ALL_KNOWN_PKGS < <( (extract_dependencies_sh_packages
  extract_power_user_sh_packages
  extract_fpm_hard_depends) | sort -u)
CHECKED=0
for f in "$REPO_ROOT"/install/config/*.sh; do
  name=$(grep -m1 -oP '(?<=dpkg -s ")[^"]+' "$f" || true)
  [[ -z "$name" ]] && continue
  CHECKED=$((CHECKED + 1))
  if ! printf '%s\n' "${ALL_KNOWN_PKGS[@]}" | grep -qxF "$name"; then
    echo "  FAIL - $(basename "$f") guards on \`dpkg -s \"$name\"\`, but '$name' isn't in dependencies.sh, power-user.sh, or build-package-ohmydebn.sh"
    FAIL=$((FAIL + 1))
  fi
done
echo "  checked $CHECKED guarded config files"

# -- check 8: every ohmydebn-menu case arm can actually match its own menu --
#
# ohmydebn-menu has two different case-statement styles: `menu "Title"
# "items"` immediately followed by `case "$MENU_RESULT" in ...` (dispatches
# on a displayed selection - checked here; see menu()'s own comment in
# ohmydebn-menu for why this isn't `case $(menu "Title" "items") in` in one
# statement anymore) and `case "${1,,}" in ...` in go_to_menu() (dispatches
# on a CLI argument, not a menu selection - deliberately not covered by
# this check). Scoped per block (not a whole-file keyword pool) so a
# keyword from one menu can't spuriously "match" unrelated text in a
# different menu elsewhere in the file.

echo
echo "-- ohmydebn-menu case-arm consistency --"
MENU_FILE="$REPO_ROOT/bin/ohmydebn-menu"
CHECKED=0
# Every `menu "Title" "items"` call in the file, except show_main_menu's -
# that one hands its result to go_to_menu instead of a case block of its
# own (see check 10's own exclusion of it below), so it's filtered out
# here by checking what actually follows rather than by name: a real
# case-block start always has `case "$MENU_RESULT" in` on the very next
# line.
mapfile -t ALL_MENU_CALLS < <(grep -n '^\s*menu "' "$MENU_FILE" | cut -d: -f1)
BLOCK_STARTS=()
for start in "${ALL_MENU_CALLS[@]}"; do
  next_line=$(sed -n "$((start + 1))p" "$MENU_FILE")
  [[ "$next_line" == *'case "$MENU_RESULT" in'* ]] && BLOCK_STARTS+=("$start")
done
for start in "${BLOCK_STARTS[@]}"; do
  rel_end=$(tail -n "+$start" "$MENU_FILE" | grep -n '^\s*esac' | head -1 | cut -d: -f1)
  end=$((start + rel_end - 1))
  block=$(sed -n "${start},${end}p" "$MENU_FILE")
  items=$(echo "$block" | grep -oP 'menu "[^"]*" "\K[^"]*' | head -1)
  while IFS= read -r kw; do
    [[ -z "$kw" ]] && continue
    CHECKED=$((CHECKED + 1))
    if [[ "$items" != *"$kw"* ]]; then
      echo "  FAIL - case arm '*${kw}*)' (block starting at line $start) doesn't match any item in its own menu"
      FAIL=$((FAIL + 1))
    fi
  done < <(echo "$block" | grep -oP '^\s*\*\K[^*]+(?=\*\))')
done
echo "  checked $CHECKED case arms across menu()-driven blocks"

# -- check 9: no two keybindings bind the same key combo --

echo
echo "-- no duplicate keybindings --"
mapfile -t ALL_BINDINGS < <(grep -ohP '\[[^\]]*\]' \
  "$REPO_ROOT/install/keybinding/keybinding-cinnamon.txt" "$REPO_ROOT/install/keybinding/keybinding-custom.txt" |
  tr -d "[]'" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')
while IFS= read -r combo; do
  [[ -z "$combo" ]] && continue
  echo "  FAIL - keybinding '$combo' is bound more than once"
  FAIL=$((FAIL + 1))
done < <(printf '%s\n' "${ALL_BINDINGS[@]}" | sort | uniq -d)
echo "  checked ${#ALL_BINDINGS[@]} key-combo assignments"

# -- check 10: ohmydebn-menu-picker's flattened search list stays in sync
#              with the real nested menu tree it's generated from --
#
# menu_tree_flatten() (bin/ohmydebn-menu-tree) walks the same case-statement
# structure check 8 above already validated arm-by-arm - that's a load-
# bearing precondition here, not a coincidence: if check 8 is failing, this
# check's pairing logic has nothing reliable to walk.

echo
echo "-- flattened menu-picker search list stays in sync with the real menu tree --"
# shellcheck disable=SC2034 # read by menu_tree_flatten() in ohmydebn-menu-tree
MT_SKIP_LABELS=(Apps)
mapfile -t FLAT < <(menu_tree_flatten "$MENU_FILE" 2>/dev/null)
if [[ ${#FLAT[@]} -eq 0 ]]; then
  echo "  FAIL - menu_tree_flatten produced zero leaves"
  FAIL=$((FAIL + 1))
fi

mapfile -t FLAT_DUPES < <(printf '%s\n' "${FLAT[@]}" | cut -f1 | sort | uniq -d)
for dupe in "${FLAT_DUPES[@]}"; do
  echo "  FAIL - breadcrumb '$dupe' is produced by more than one leaf"
  FAIL=$((FAIL + 1))
done

mapfile -t ALL_MENU_FUNCS < <(grep -oP '^show_[a-zA-Z0-9_]+_menu(?=\(\) \{)' "$MENU_FILE")
for func in "${ALL_MENU_FUNCS[@]}"; do
  # show_main_menu has no case $(menu ...) block of its own - it builds the
  # go_items string and hands off to menu() (which calls
  # ohmydebn-menu-picker) instead.
  [[ "$func" == "show_main_menu" ]] && continue
  grep -qP "\)\s*${func}\s*;;" "$MENU_FILE" ||
    { echo "  FAIL - $func is defined but no case arm targets it"; FAIL=$((FAIL + 1)); }
done
echo "  checked ${#FLAT[@]} flattened leaves"

# ohmydebn-menu's menu() looks up its caller's breadcrumb prefix via
# menu_tree_paths() by function name, assuming each show_*_menu is
# reachable via exactly one path (confirmed true today by hand-tracing
# every case-arm target, but nothing else enforces it) - a function
# reachable two ways would make that lookup pick one arbitrarily and scope
# search results by the wrong prefix.
mapfile -t PATHS < <(menu_tree_paths "$MENU_FILE" 2>/dev/null)
mapfile -t PATH_DUPES < <(printf '%s\n' "${PATHS[@]}" | cut -f1 | sort | uniq -d)
for dupe in "${PATH_DUPES[@]}"; do
  echo "  FAIL - $dupe is reachable via more than one breadcrumb path"
  FAIL=$((FAIL + 1))
done
echo "  checked ${#PATHS[@]} func -> breadcrumb paths"

# -- check 11: rofi is never invoked anywhere - a regression guard, not a
#              consistency-of-something-else check, for the ohmydebn-menu-
#              picker/-theme-carousel work that replaced every real rofi
#              call site this project had --

echo
echo "-- rofi is not invoked anywhere (regression guard) --"
mapfile -t ROFI_HITS < <(grep -rlE '/usr/bin/rofi\b' "$REPO_ROOT/bin" "$REPO_ROOT/install" 2>/dev/null)
for f in "${ROFI_HITS[@]}"; do
  echo "  FAIL - ${f#"$REPO_ROOT"/} still invokes /usr/bin/rofi directly"
  FAIL=$((FAIL + 1))
done
echo "  checked bin/ and install/ for direct rofi invocations"

# -- check 12: the GTK pickers never manually scale their own window sizes
#              - a regression guard for a real bug: ohmydebn-menu-picker
#              used to pre-multiply its width by the monitor's Muffin scale
#              factor (a leftover from rofi's DPI/theme-unit model) before
#              handing it to Gtk.Window.set_default_size(), which already
#              applies that same scale factor itself - confirmed by hand
#              (identical set_default_size() calls produced a real 480x200
#              X11 window at GDK_SCALE=1 and a real 960x400 one at
#              GDK_SCALE=2, no other code involved). Pre-multiplying again
#              would quadruple the window's on-screen area on a 2x
#              display. ohmydebn-scale/ohmydebn-picker-width (the two
#              scripts this used) are deleted entirely, but this guards
#              against the same pattern creeping back in some other form
#              (e.g. calling Muffin's DisplayConfig directly) too. --

echo
echo "-- GTK pickers don't manually pre-scale window sizes (regression guard) --"
mapfile -t SCALE_HITS < <(grep -lE 'ohmydebn-scale|ohmydebn-picker-width|Muffin\.DisplayConfig' \
  "$REPO_ROOT/bin/ohmydebn-menu-picker" "$REPO_ROOT/bin/ohmydebn-theme-carousel" 2>/dev/null)
for f in "${SCALE_HITS[@]}"; do
  echo "  FAIL - ${f#"$REPO_ROOT"/} references a manual scale-query mechanism - GTK already scales set_default_size()/fullscreen() automatically"
  FAIL=$((FAIL + 1))
done
echo "  checked the 2 GTK pickers for manual scale pre-multiplication"

# -- check 13: every menu-item icon glyph resolves natively in CaskaydiaMono
#              Nerd Font, not some fallback font - a regression guard for a
#              real bug: several rows (Cybersecurity, cliamp, GIMP, UxPlay)
#              used a plain Unicode emoji with a text-presentation variation
#              selector (e.g. the magnifying glass), which that font doesn't
#              actually contain. Pango silently substituted a taller system
#              font (Symbola/Unifont) for just that row, inflating its
#              height above every sibling row in the same list - confirmed
#              via `fc-match`, fixed by swapping in real Nerd Font PUA
#              glyphs that already resolve in-font like every other icon.

echo
echo "-- menu-item icons resolve in CaskaydiaMono Nerd Font (no font-fallback regression) --"
if ! command -v fc-match >/dev/null 2>&1; then
  echo "  SKIP - fc-match not installed"
else
  ICON_RESULT=$(python3 - "$MENU_FILE" <<'PYEOF'
import re
import subprocess
import sys

menu_file = sys.argv[1]
with open(menu_file, encoding="utf-8") as f:
    src = f.read()

# The two shapes items strings are written in this file: inline in a
# `menu "Title" "items"` call (see menu()'s own comment in ohmydebn-menu
# for why this isn't `case $(menu "Title" "items") in` as one statement
# anymore), or built up in a local var first (today, only show_main_menu's
# go_items) and referenced as "$go_items".
items_strings = re.findall(r'^\s*menu "[^"]*" "([^"]*)"$', src, re.MULTILINE)
m = re.search(r'local go_items="([^"]*)"', src)
if m:
    items_strings.append(m.group(1))

icons = set()
for items in items_strings:
    for line in items.split("\\n"):
        if not line:
            continue
        icon_match = re.match(r"^(\S+)\s", line)
        if icon_match:
            icons.add(icon_match.group(1))

fail = 0
for icon in sorted(icons):
    charset = ",".join(f"{ord(c):x}" for c in icon)
    result = subprocess.run(
        ["fc-match", f"CaskaydiaMono Nerd Font:charset={charset}"],
        capture_output=True, text=True, check=False,
    )
    if 'CaskaydiaMono Nerd Font' not in result.stdout:
        fail += 1
        codepoints = "/".join(f"U+{ord(c):04X}" for c in icon)
        print(f"  FAIL - icon '{icon}' ({codepoints}) isn't in CaskaydiaMono Nerd "
              f"Font, falls back to: {result.stdout.strip()}")

print(f"  checked {len(icons)} unique icon glyphs")
sys.exit(1 if fail else 0)
PYEOF
)
  echo "$ICON_RESULT"
  ICON_FAILS=$(grep -c '^  FAIL' <<<"$ICON_RESULT" || true)
  FAIL=$((FAIL + ICON_FAILS))
fi

# -- check 14: ohmydebn-menu-picker's row labels stay ellipsized - a
#              regression guard for a real bug: a search result's display
#              text is a full breadcrumb (e.g. "Install > Virtualization >
#              Virtual Machine Manager (Advanced)") with no length limit,
#              but the picker window's width is fixed - without Pango
#              ellipsizing, a long one just silently ran past the edge of
#              the window with no visual indication anything was missing
#              (confirmed by hand: same text, same length, just invisible
#              past the cutoff). Can't test the actual rendered behavior
#              here - this whole suite deliberately runs the same with or
#              without a real display (see test-python-pickers.py's
#              top-of-file comment), and even a bare Gtk.Label() hard-
#              crashes without one (confirmed by hand: "Gtk-ERROR: Can't
#              create a GtkStyleContext without a display connection") -
#              so this only guards the fix itself against silently
#              regressing out of the source, the same reasoning as check
#              12 above.

echo
echo "-- ohmydebn-menu-picker row labels stay ellipsized (regression guard) --"
PICKER_FILE="$REPO_ROOT/bin/ohmydebn-menu-picker"
if ! grep -q 'set_ellipsize(Pango.EllipsizeMode.END)' "$PICKER_FILE"; then
  echo "  FAIL - populate()'s row label no longer ellipsizes - a long search-result breadcrumb will silently run past the window's fixed width again with no visual indication anything's missing"
  FAIL=$((FAIL + 1))
else
  echo "  ellipsize is set on the row label"
fi

echo
echo "-- populate() keeps this window sized to its content (regression guard) --"
# resize_to_content()'s own comment explains why this matters: Cinnamon/
# Muffin silently ignores plain resize() on this undecorated DIALOG-hint
# window once it's mapped (confirmed by hand), which --serve mode's window
# always is by the time reload()/on_search_changed() change what's showing
# - so without the set_geometry_hints()-forced resize below, any screen
# with more rows than whatever was visible at this window's first-ever
# layout gets a scrollbar it can never grow out of for the rest of its
# life. This is exactly what broke when Install > AI's items moved to
# their own top-level AI menu and pushed the Go screen from 11 to 12 rows.
if ! grep -q 'def resize_to_content' "$PICKER_FILE"; then
  echo "  FAIL - resize_to_content() is gone from $(basename "$PICKER_FILE") - screens with more rows than this window's first-ever layout will silently get a permanent scrollbar again"
  FAIL=$((FAIL + 1))
elif ! grep -q 'self.resize_to_content(len(rows))' "$PICKER_FILE"; then
  echo "  FAIL - populate() no longer calls resize_to_content() - a reload() or search keystroke that changes the row count won't resize this window anymore"
  FAIL=$((FAIL + 1))
elif ! grep -q 'set_geometry_hints' "$PICKER_FILE"; then
  echo "  FAIL - resize_to_content() no longer uses set_geometry_hints() - a plain resize() alone is silently ignored post-map on this window (confirmed by hand), so this would regress right back to the bug it fixed"
  FAIL=$((FAIL + 1))
else
  echo "  resize_to_content() exists, is wired into populate(), and forces the resize via WM size hints"
fi

echo
echo "-- finish() hides the persistent-picker window before running a pick (regression guard) --"
# A real report: "the menu remains visible until the launched app is
# closed" - e.g. picking About or Demo. --serve mode's window stays alive
# across a whole ohmydebn-menu session (see resize_to_content's comment on
# why), and finish() used to leave it visible after sending a pick back,
# trusting reload() to repaint it for the next screen - true for submenu
# navigation, but a leaf pick runs its command synchronously on the bash
# side with no further reload() coming, so nothing hid the window until
# that command finished and the whole session's EXIT trap finally fired.
# finish() now hides it immediately on every pick (real or cancelled);
# reload() re-shows it if another screen follows.
FINISH_START=$(grep -n '^    def finish(self, value):' "$PICKER_FILE" | head -1 | cut -d: -f1)
FINISH_REL_END=$(tail -n "+$FINISH_START" "$PICKER_FILE" | grep -n '^    def \|^def ' | sed -n '2p' | cut -d: -f1)
FINISH_BLOCK=$(sed -n "${FINISH_START},$((FINISH_START + FINISH_REL_END - 2))p" "$PICKER_FILE")
if [[ -z "$FINISH_START" ]]; then
  echo "  FAIL - couldn't find finish() in $(basename "$PICKER_FILE") - did it get renamed?"
  FAIL=$((FAIL + 1))
elif [[ "$(grep -c 'self\.hide()' <<<"$FINISH_BLOCK")" -lt 2 ]]; then
  echo "  FAIL - finish() no longer hides the window on both the real-value and cancelled paths back to on_result - a leaf pick (About, Demo, ...) will stay visible again until whatever it launches closes"
  FAIL=$((FAIL + 1))
elif ! grep -q 'self.show()' "$PICKER_FILE"; then
  echo "  FAIL - nothing re-shows the window after finish() hides it - every screen after the first pick of a session would stay invisible"
  FAIL=$((FAIL + 1))
else
  echo "  finish() hides the window on both on_result paths, and something re-shows it for the next screen"
fi

echo
echo "-- show_ai_menu picks stay in sync with ohmydebn-ai-set-default --"
# ohmydebn-ai (Super+A) launches whatever bin/ohmydebn-menu's
# show_ai_menu last recorded via ohmydebn-ai-set-default - see that
# function's own comment. There's no separate "set default AI" menu, so if
# a pick's set-default call names the wrong tool (or is missing/reordered
# after the launcher instead of before it), Super+A silently launches
# something other than what was just picked.
AI_MENU_START=$(grep -n '^show_ai_menu() {' "$MENU_FILE" | head -1 | cut -d: -f1)
AI_MENU_REL_END=$(tail -n "+$AI_MENU_START" "$MENU_FILE" | grep -n '^}' | head -1 | cut -d: -f1)
AI_MENU_END=$((AI_MENU_START + AI_MENU_REL_END - 1))
AI_MENU_BLOCK=$(sed -n "${AI_MENU_START},${AI_MENU_END}p" "$MENU_FILE")
declare -A AI_ARM_TO_DEFAULT_NAME=(
  [OpenCode]=opencode
  [Claude]=claude-code
  [ChatGPT]=chatgpt
  [Pi]=pi
  [Antigravity]=antigravity
  [VSCode]=vscode
)
CHECKED=0
for arm in "${!AI_ARM_TO_DEFAULT_NAME[@]}"; do
  CHECKED=$((CHECKED + 1))
  expected="${AI_ARM_TO_DEFAULT_NAME[$arm]}"
  # The arm's own block: from its `*Arm*)` line up to the next `;;`.
  arm_block=$(echo "$AI_MENU_BLOCK" | awk -v pat="\\\*${arm}\\\*\\)" '
    $0 ~ pat { capturing=1 }
    capturing { print }
    capturing && /;;/ { exit }
  ')
  if [[ -z "$arm_block" ]]; then
    echo "  FAIL - show_ai_menu has no '*${arm}*)' arm anymore (expected one setting default '$expected')"
    FAIL=$((FAIL + 1))
  elif ! echo "$arm_block" | grep -qP "ohmydebn-ai-set-default $expected\b"; then
    echo "  FAIL - '*${arm}*)' arm doesn't call 'ohmydebn-ai-set-default $expected' - Super+A won't launch what this pick just opened"
    FAIL=$((FAIL + 1))
  fi
done
echo "  checked $CHECKED AI picks"

echo
echo "-- ohmydebn-ai and ohmydebn-ai-set-default agree on the set of AI names --"
# Independent of show_ai_menu's own picks (checked above): if a name
# is ever added to one script's case statement without the other, either
# ohmydebn-ai-set-default accepts a name ohmydebn-ai can't launch (silently
# no-ops - its case has no matching arm and falls through with nothing
# exec'd), or ohmydebn-ai-set-default rejects a name ohmydebn-menu is
# actually trying to set as the new default.
AI_SCRIPT="$REPO_ROOT/bin/ohmydebn-ai"
AI_SET_DEFAULT_SCRIPT="$REPO_ROOT/bin/ohmydebn-ai-set-default"
mapfile -t AI_DISPATCH_NAMES < <(grep -oP '^(?!case|esac)\K[a-z][a-z-]*(?=\) exec)' "$AI_SCRIPT" | sort -u)
# The valid-names line is a single "a | b | c)" case pattern, not one name
# per line - pull that whole line out, then split it on '|'.
AI_VALID_LINE=$(grep -E '^[a-z][a-z-]*( \| [a-z][a-z-]*)+\)' "$AI_SET_DEFAULT_SCRIPT")
mapfile -t AI_VALID_NAMES < <(echo "${AI_VALID_LINE%)*}" | tr '|' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)
if [[ "$(printf '%s\n' "${AI_DISPATCH_NAMES[@]}")" != "$(printf '%s\n' "${AI_VALID_NAMES[@]}")" ]]; then
  echo "  FAIL - ohmydebn-ai's dispatch names (${AI_DISPATCH_NAMES[*]}) don't match ohmydebn-ai-set-default's accepted names (${AI_VALID_NAMES[*]})"
  FAIL=$((FAIL + 1))
else
  echo "  both scripts agree on: ${AI_DISPATCH_NAMES[*]}"
fi

echo
echo "-- local-share.sh and theme-carousel agree on the legacy aether desktop filenames --"
# Both remove the same stale per-user desktop files (see either one's own
# comment for why) - install/cleanup/local-share.sh sweeps them once per
# ohmydebn-update, bin/ohmydebn-theme-carousel's open_browse_themes()
# re-sweeps right before the one action that can trigger aether to
# recreate one. If either list drifts from the other, one of the two
# sweep points silently stops protecting against a name the other still
# knows about.
LOCAL_SHARE_SH="$REPO_ROOT/install/cleanup/local-share.sh"
THEME_CAROUSEL="$REPO_ROOT/bin/ohmydebn-theme-carousel"
LEGACY_LINE=$(grep -E '^for FILE in .*\.desktop.*; do$' "$LOCAL_SHARE_SH")
mapfile -t LEGACY_BASH_NAMES < <(echo "${LEGACY_LINE#for FILE in }" | sed 's/; do$//' | tr ' ' '\n' | sort -u)
PY_BLOCK=$(sed -n '/^LEGACY_AETHER_DESKTOP_FILES = ($/,/^)$/p' "$THEME_CAROUSEL")
mapfile -t LEGACY_PY_NAMES < <(echo "$PY_BLOCK" | grep -oP '"\K[a-zA-Z0-9_.-]+\.desktop(?=")' | sort -u)
if [[ -z "$LEGACY_LINE" ]]; then
  echo "  FAIL - couldn't find the 'for FILE in ...desktop...; do' loop in $(basename "$LOCAL_SHARE_SH") - did it get restructured?"
  FAIL=$((FAIL + 1))
elif [[ -z "$PY_BLOCK" ]]; then
  echo "  FAIL - couldn't find LEGACY_AETHER_DESKTOP_FILES in $(basename "$THEME_CAROUSEL") - did it get renamed?"
  FAIL=$((FAIL + 1))
elif [[ "$(printf '%s\n' "${LEGACY_BASH_NAMES[@]}")" != "$(printf '%s\n' "${LEGACY_PY_NAMES[@]}")" ]]; then
  echo "  FAIL - local-share.sh's legacy names (${LEGACY_BASH_NAMES[*]}) don't match theme-carousel's LEGACY_AETHER_DESKTOP_FILES (${LEGACY_PY_NAMES[*]})"
  FAIL=$((FAIL + 1))
else
  echo "  both agree on: ${LEGACY_BASH_NAMES[*]}"
fi

echo
echo "-- open_browse_themes() actually calls remove_legacy_aether_desktop_files() --"
# The function working in isolation (covered in test-python-pickers.py) is
# not the same as it actually being called from the one place it matters -
# a future edit to open_browse_themes() could drop the call while leaving
# the function itself, and its own unit tests, untouched and still green.
BROWSE_START=$(grep -n '^    def open_browse_themes(self):' "$THEME_CAROUSEL" | head -1 | cut -d: -f1)
BROWSE_REL_END=$(tail -n "+$BROWSE_START" "$THEME_CAROUSEL" | grep -n '^    def \|^def ' | sed -n '2p' | cut -d: -f1)
if [[ -z "$BROWSE_START" ]]; then
  echo "  FAIL - couldn't find open_browse_themes() in $(basename "$THEME_CAROUSEL") - did it get renamed?"
  FAIL=$((FAIL + 1))
else
  BROWSE_BLOCK=$(sed -n "${BROWSE_START},$((BROWSE_START + BROWSE_REL_END - 2))p" "$THEME_CAROUSEL")
  if ! grep -q 'remove_legacy_aether_desktop_files()' <<<"$BROWSE_BLOCK"; then
    echo "  FAIL - open_browse_themes() no longer calls remove_legacy_aether_desktop_files() - a stale per-user handler wouldn't be cleaned up before sending the user to a page that can trigger aether"
    FAIL=$((FAIL + 1))
  else
    echo "  open_browse_themes() calls remove_legacy_aether_desktop_files()"
  fi
fi

echo
echo "$FAIL failure(s)"
[[ $FAIL -eq 0 ]]
