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
# No explicit MT_SKIP_LABELS here on purpose - this exercises
# ohmydebn-menu-tree's own MT_DEFAULT_SKIP_LABELS ("Other Apps") the same
# way every real caller does (ohmydebn-menu-picker's load_leaves(), the
# ohmydebn-package-build repo's shipped-cache pregeneration), rather than
# hand-repeating the literal a fourth time - that repetition is exactly
# what once let one copy silently drift to a stale "Apps" for a long time
# without anything noticing.
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

# Regression guard for a real bug: _mt_menu_block_start() searched forward
# from a function's own opening line for the first `menu "` call anywhere
# in the *rest of the file*, not bounded to that function's own body. A
# function with no menu() call of its own (show_other_apps_menu, which
# talks to the persistent picker directly instead - see its own comment in
# ohmydebn-menu) silently "borrowed" whatever function's menu() call
# happened to follow it in the file - confirmed live: once Other Apps
# became reachable through _mt_walk() (nested under Apps) rather than
# skipped outright via MT_SKIP_LABELS (which only the top-level walk in
# _mt_flatten_uncached ever checks), it inherited show_containers_menu's
# own Docker/Podman/Distrobox items instead of correctly reporting nothing
# to walk. A synthetic fixture, not the real menu file, so this keeps
# catching a regression in the tool itself regardless of which real
# function happens to follow which.
echo
echo "-- _mt_menu_block_start() doesn't borrow a following function's menu() call (regression guard) --"
# Deliberately invoked via a fresh `bash -c` below, not a plain call in
# this already-running script - this file's own `set -uo pipefail`
# (line 16) would silently make `$(pipeline) || return 1` behave
# correctly even with the exact bug this guards against, since pipefail
# propagates a pipeline's real failure through trailing `head`/`cut`
# commands that would otherwise exit 0 on empty input. ohmydebn-menu-tree
# explicitly never sets pipefail itself (every caller sources it with its
# own flags - see its header comment), and its real vulnerable caller,
# ohmydebn-menu-picker's run_menu_tree(), is exactly this: a plain
# `bash -c` with no pipefail. Testing under this script's own pipefail
# would only prove the bug can't happen *here*, not that it can't happen
# in the one place it actually did.
BORROW_FIXTURE=$(mktemp)
printf 'no_menu_call_test() {\n  echo "no menu() call in this function"\n}\n\nhas_menu_call_test() {\n  menu "Real" "  Item"\n  case "$MENU_RESULT" in\n  *) : ;;\n  esac\n}\n' >"$BORROW_FIXTURE"
if bash -c 'source "$1"; _mt_menu_block_start "$2" no_menu_call_test' _ "$REPO_ROOT/bin/ohmydebn-menu-tree" "$BORROW_FIXTURE" >/dev/null 2>&1; then
  echo "  FAIL - found a menu() block for a function with none of its own (borrowed the next function's instead)"
  FAIL=$((FAIL + 1))
else
  echo "  correctly reports no block for a function with no menu() call"
fi
rm -f "$BORROW_FIXTURE"

# Regression guard for a second real bug, found alongside the one above:
# _mt_item_labels()/_mt_flatten_uncached()'s label extraction used
# `^\S+\s+\K.*`, requiring a leading icon character before the separating
# spaces - a handful of real items (Cybersecurity, Editor, Virtualization,
# ...) have never carried one, so grep's `^\S+` anchor simply failed to
# match and silently produced no output at all for that one line, dropping
# the item's label (and so its whole subtree) out of the flattened search
# list with no warning, no crash, nothing to notice. A synthetic
# icon-less fixture, not the real menu file, so this keeps catching a
# regression in the tool itself even if those specific items eventually
# gain real icons.
echo
echo "-- _mt_item_labels() extracts a label even without a leading icon (regression guard) --"
ICONLESS_FIXTURE=$(mktemp)
printf 'iconless_test_menu() {\n  menu "Test" "  Has No Icon"\n  case "$MENU_RESULT" in\n  *) : ;;\n  esac\n}\n' >"$ICONLESS_FIXTURE"
mapfile -t ICONLESS_LABELS < <(_mt_item_labels "$ICONLESS_FIXTURE" "$(_mt_menu_block_start "$ICONLESS_FIXTURE" iconless_test_menu)")
rm -f "$ICONLESS_FIXTURE"
if [[ "${ICONLESS_LABELS[0]:-}" != "Has No Icon" ]]; then
  echo "  FAIL - an icon-less item's label was dropped instead of extracted (got: ${ICONLESS_LABELS[*]:-<nothing>})"
  FAIL=$((FAIL + 1))
else
  echo "  correctly extracts an icon-less item's label"
fi

echo
echo "-- ohmydebn-menu-picker's ALWAYS_SUBMENU_LABELS matches ohmydebn-menu-tree's MT_DEFAULT_SKIP_LABELS --"
# Same set of names by construction: a label excluded from the static
# menu-tree walk (MT_DEFAULT_SKIP_LABELS) has no leaves for
# find_submenu_labels() to match against, so it needs the exact same
# label hand-added back via ALWAYS_SUBMENU_LABELS to still earn its ">"
# marker - see that constant's own comment in ohmydebn-menu-picker. Two
# independent hand-copies of the same set is exactly the kind of
# duplication that already let MT_SKIP_LABELS itself drift stale once;
# this catches the two ever disagreeing instead of relying on nobody
# forgetting to update both.
TREE_DEFAULT_SKIP=$(printf '%s\n' "${MT_DEFAULT_SKIP_LABELS[@]}" | sort)
PICKER_ALWAYS_SUBMENU=$(python3 -c "
import re
with open('$REPO_ROOT/bin/ohmydebn-menu-picker', encoding='utf-8') as f:
    src = f.read()
m = re.search(r'ALWAYS_SUBMENU_LABELS = \{([^}]*)\}', src)
labels = re.findall(r'\"([^\"]*)\"', m.group(1)) if m else []
print('\n'.join(sorted(labels)))
")
if [[ "$TREE_DEFAULT_SKIP" != "$PICKER_ALWAYS_SUBMENU" ]]; then
  echo "  FAIL - MT_DEFAULT_SKIP_LABELS ($TREE_DEFAULT_SKIP) != ALWAYS_SUBMENU_LABELS ($PICKER_ALWAYS_SUBMENU)"
  FAIL=$((FAIL + 1))
else
  echo "  both agree on: $(tr '\n' ' ' <<<"$TREE_DEFAULT_SKIP")"
fi

# Regression guard for a real bug: go_to_menu()'s case arms are matched in
# file order against a lowercased category label, and bash's `case` picks
# the *first* arm whose glob matches - not the most specific one. Adding
# "Containerization" to the top level once silently routed to show_ai_menu
# instead of show_containerization_menu, because "*ai*)" was listed first
# and "containerization" contains "ai" as a substring (conta-AI-nerization)
# - found only by hand-checking menu_tree_paths()'s output, nothing
# automated caught it. Generalizes that check: for every top-level
# show_*_menu function (breadcrumb with no " > " - a nested one like
# show_install_style_menu's name isn't expected to reduce this cleanly,
# since it carries its parent's own name too), stripping "show_"/"_menu"
# from the function name must reproduce its own category label exactly -
# if it doesn't, something else's case arm shadowed the real one.
echo
echo "-- Go-menu categories resolve to their own show_*_menu, not a shadowed earlier arm --"
CHECKED=0
for path in "${PATHS[@]}"; do
  func="${path%%$'\t'*}"
  breadcrumb="${path#*$'\t'}"
  [[ "$breadcrumb" == *" > "* ]] && continue
  CHECKED=$((CHECKED + 1))
  core="${func#show_}"
  core="${core%_menu}"
  # A multi-word category's function name only has to reflect ONE of its
  # words, not the whole thing concatenated - e.g. a category named
  # "Foo Bar" only needs its dispatch keyword to be "foo" or "bar", not
  # "foobar". Checking membership in the word list, not equality against
  # the whole label, avoids that false positive while still catching the
  # real bug:
  # "containerization" is one word with no spaces, so show_ai_menu's core
  # "ai" (not equal to, and not a member of, {"containerization"}) still
  # fails exactly as it should.
  mapfile -t words < <(echo "$breadcrumb" | tr '[:upper:]' '[:lower:]' | tr ' ' '\n')
  match=false
  for word in "${words[@]}"; do
    [[ "$core" == "$word" ]] && match=true && break
  done
  if [[ "$match" == false ]]; then
    echo "  FAIL - $func resolves to \"$breadcrumb\", but its own name implies \"$core\" - check go_to_menu()'s case-arm order for a shadowing keyword"
    FAIL=$((FAIL + 1))
  fi
done
echo "  checked $CHECKED top-level Go-menu categories"

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
echo "-- finish() closes the persistent-picker process before running a leaf pick (regression guard) --"
# A real report: "the menu remains visible until the launched app is
# closed" - e.g. picking About or Demo. --serve mode's window stays alive
# across a whole ohmydebn-menu session (see resize_to_content's comment on
# why), and finish() used to leave it visible after sending a pick back,
# trusting reload() to repaint it for the next screen - true for submenu
# navigation, but a leaf pick runs its command synchronously on the bash
# side with no further reload() coming, so nothing hid the window until
# that command finished and the whole session's EXIT trap finally fired.
#
# finish() no longer hides immediately, though - that traded the stuck-open
# bug for a different real report, a visible hide-then-reshow flash on
# every ordinary submenu pick (the common case, and fast: no process spawn,
# just local pipe I/O). It now schedules a close via _schedule_close()
# instead, and reload() cancels it if another screen follows within
# CLOSE_DELAY_MS - which the fast submenu-navigation round trip always
# does, so that path never even hides, let alone quits. bin/ohmydebn-menu
# never loops back to show_main_menu, so a pick with no reload() following
# it means this session's picker really is done for good - the deferred
# callback actually quits the process (Gtk.main_quit(), same as the
# original one-shot mode's own finish()), not just hides the window, so it
# doesn't linger as a hidden process until whatever it launched closes and
# the whole ohmydebn-menu script's EXIT trap eventually reaps it.
FINISH_START=$(grep -n '^    def finish(self, value):' "$PICKER_FILE" | head -1 | cut -d: -f1)
FINISH_REL_END=$(tail -n "+$FINISH_START" "$PICKER_FILE" | grep -n '^    def \|^def ' | sed -n '2p' | cut -d: -f1)
FINISH_BLOCK=$(sed -n "${FINISH_START},$((FINISH_START + FINISH_REL_END - 2))p" "$PICKER_FILE")
if [[ -z "$FINISH_START" ]]; then
  echo "  FAIL - couldn't find finish() in $(basename "$PICKER_FILE") - did it get renamed?"
  FAIL=$((FAIL + 1))
elif [[ "$(grep -c 'self\._schedule_close()' <<<"$FINISH_BLOCK")" -lt 2 ]]; then
  echo "  FAIL - finish() no longer schedules a close on both the real-value and cancelled paths back to on_result - a leaf pick (About, Demo, ...) will stay visible again until whatever it launches closes"
  FAIL=$((FAIL + 1))
elif ! grep -q 'def _deferred_close' "$PICKER_FILE" || ! grep -A5 'def _deferred_close' "$PICKER_FILE" | grep -q 'Gtk\.main_quit()'; then
  echo "  FAIL - _schedule_close()'s own timeout callback no longer actually quits the process - a leaf pick would leave it hidden but running forever now"
  FAIL=$((FAIL + 1))
elif ! grep -q 'GLib\.source_remove' "$PICKER_FILE"; then
  echo "  FAIL - nothing cancels a pending deferred close from reload() - every ordinary submenu pick would regress back to the hide-then-reshow flash (or worse, an outright quit) this was written to fix"
  FAIL=$((FAIL + 1))
elif ! grep -q 'self.show()' "$PICKER_FILE"; then
  echo "  FAIL - nothing re-shows the window when reload() cancels a pending close in time - every screen after the first pick of a session would stay invisible"
  FAIL=$((FAIL + 1))
else
  echo "  finish() schedules a close on both on_result paths, reload() cancels it for a fast submenu round trip, and the window stays visible/shown throughout that path"
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
echo "-- ohmydebn-ai-cli agrees with ohmydebn-ai-set-default on the set of AI names --"
# Same drift risk as the check above, for the `a` alias's target: if a name
# is ever added to ohmydebn-ai-set-default's case statement without also
# adding a matching arm to ohmydebn-ai-cli (or vice versa), Super+A and `a`
# would silently disagree on what the same stored default launches.
AI_CLI_SCRIPT="$REPO_ROOT/bin/ohmydebn-ai-cli"
mapfile -t AI_CLI_DISPATCH_NAMES < <(grep -oP '^(?!case|esac)\K[a-z][a-z-]*(?=\) exec)' "$AI_CLI_SCRIPT" | sort -u)
if [[ "$(printf '%s\n' "${AI_CLI_DISPATCH_NAMES[@]}")" != "$(printf '%s\n' "${AI_VALID_NAMES[@]}")" ]]; then
  echo "  FAIL - ohmydebn-ai-cli's dispatch names (${AI_CLI_DISPATCH_NAMES[*]}) don't match ohmydebn-ai-set-default's accepted names (${AI_VALID_NAMES[*]})"
  FAIL=$((FAIL + 1))
else
  echo "  both scripts agree on: ${AI_CLI_DISPATCH_NAMES[*]}"
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
echo "-- floating-terminal launches always pass a title (regression guard) --"
# Both ohmydebn-launch-floating-terminal-with-presentation and
# ohmydebn-launch-floating-terminal used to take just a <command>, which
# left every on-demand app's install/run terminal showing "Alacritty" in
# the taskbar no matter what was actually running - confirmed live and
# fixed by making <title> a required first argument. Guards against the
# next new on-demand app script reintroducing that bug by passing the
# install-script path as the first arg again instead of a quoted title:
# \K only captures the single character right after the helper name and
# its trailing spaces, so a real call (title always starts with a quote,
# whether literal or a variable like "$1") passes, while the old buggy
# shape (a bare /path/to/..., starting with /) fails.
mapfile -t TITLELESS_HITS < <(grep -rHnoP 'ohmydebn-launch-floating-terminal(-with-presentation)? +\K.' "$REPO_ROOT/bin" "$REPO_ROOT/install" 2>/dev/null | grep -v ':"$')
for hit in "${TITLELESS_HITS[@]}"; do
  file="${hit%%:*}"
  echo "  FAIL - ${file#"$REPO_ROOT"/} calls a floating-terminal helper with a bare path instead of a quoted title"
  FAIL=$((FAIL + 1))
done
echo "  checked floating-terminal helper call sites in bin/ and install/"

echo
echo "-- pre-tiled launchers' gTile grids match their intended \"Tile with gaps N ...\" keybindings --"
# Each of these launches a window and immediately tiles it via
# ohmydebn-gtile-apply - ohmydebn-terminal-tiled directly; every
# OHMYDEBN_TILE_GRID-override launcher indirectly through
# ohmydebn-terminal-tiled; every ohmydebn-launch-tiled-based launcher
# indirectly through ohmydebn-launch-tiled - claiming (in its own
# comment) to match a specific named "Tile with gaps N ..." keybinding
# exactly, so a freshly launched window already looks like you'd just
# re-tiled it that way yourself. This checks each claim against the real
# keybinding instead of trusting the comment, so they can't silently
# drift apart if any one of them is ever edited alone.
check_tile_grid() {
  local keybinding_label="$1" actual_grid="$2" source_desc="$3"
  local keybinding_line keybinding_grid
  keybinding_line=$(grep "\"$keybinding_label\"" "$REPO_ROOT/install/keybinding/keybinding-custom.txt")
  keybinding_grid=$(grep -oP 'TileFocusedWindow \K[0-9 ]+' <<<"$keybinding_line" | sed 's/ *$//')
  if [[ -z "$keybinding_grid" || -z "$actual_grid" ]]; then
    echo "  FAIL - couldn't find a TileFocusedWindow grid for $source_desc or \"$keybinding_label\""
    FAIL=$((FAIL + 1))
  elif [[ "$keybinding_grid" != "$actual_grid" ]]; then
    echo "  FAIL - $source_desc ($actual_grid) doesn't match \"$keybinding_label\"'s ($keybinding_grid)"
    FAIL=$((FAIL + 1))
  else
    echo "  grids match: $actual_grid ($source_desc)"
  fi
}
TERMINAL_TILED_DEFAULT_GRID=$(grep -oP 'OHMYDEBN_TILE_GRID:-\K[0-9 ]+(?=\})' "$REPO_ROOT/bin/ohmydebn-terminal-tiled")
check_tile_grid "Tile with gaps 5 full" "$TERMINAL_TILED_DEFAULT_GRID" "ohmydebn-terminal-tiled's default grid"

# Every OHMYDEBN_TILE_GRID-override launcher, paired with the named
# keybinding its own comment claims to match - add a new
# "script:keybinding label" entry here when a new one of these wrapper
# scripts is added, rather than a new copy-pasted extraction+check block.
# Reused below for the delegation check too, so the set of launchers only
# has to be listed in one place.
GRID_OVERRIDE_LAUNCHERS=(
  "ohmydebn-fastfetch-gui-tiled:Tile with gaps 9 top right corner"
  "ohmydebn-btop-gui-tiled:Tile with gaps 3 bottom right corner"
  "ohmydebn-terminal-left-tiled:Tile with gaps 4 left half"
  "ohmydebn-update-gui-tiled:Tile with gaps 6 right half"
  "ohmydebn-neovim-tiled:Tile with gaps 6 right half"
  "ohmydebn-cava-tiled:Tile with gaps 3 bottom right corner"
)
for ENTRY in "${GRID_OVERRIDE_LAUNCHERS[@]}"; do
  SCRIPT="${ENTRY%%:*}"
  LABEL="${ENTRY#*:}"
  GRID=$(grep -oP 'OHMYDEBN_TILE_GRID="\K[0-9 ]+(?=")' "$REPO_ROOT/bin/$SCRIPT")
  check_tile_grid "$LABEL" "$GRID" "$SCRIPT's grid"
done

# Every ohmydebn-launch-tiled-based launcher, same "script:keybinding
# label" shape as above - these call ohmydebn-launch-tiled directly with
# the grid as its own leading args, rather than going through
# ohmydebn-terminal-tiled, because their target app can't be reliably
# tracked by a fresh PID (see ohmydebn-launch-tiled's own comment).
LAUNCH_TILED_LAUNCHERS=(
  "ohmydebn-browser-tiled:Tile with gaps 5 full"
  "ohmydebn-keepass-tiled:Tile with gaps 5 full"
  "ohmydebn-file-manager-tiled:Tile with gaps 6 right half"
  "ohmydebn-socrates-tiled:Tile with gaps 6 right half"
  "ohmydebn-claude-code-tiled:Tile with gaps 6 right half"
  "ohmydebn-ai-tiled:Tile with gaps 6 right half"
  "ohmydebn-editor-tiled:Tile with gaps 6 right half"
  "ohmydebn-cliamp-tiled:Tile with gaps 3 bottom right corner"
  "ohmydebn-launch-webapp:Tile with gaps 6 right half"
  "ohmydebn-aether-tiled:Tile with gaps 6 right half"
  "ohmydebn-antigravity-tiled:Tile with gaps 6 right half"
  "ohmydebn-code-tiled:Tile with gaps 6 right half"
  "ohmydebn-chatgpt-tiled:Tile with gaps 6 right half"
)
for ENTRY in "${LAUNCH_TILED_LAUNCHERS[@]}"; do
  SCRIPT="${ENTRY%%:*}"
  LABEL="${ENTRY#*:}"
  GRID=$(grep -oP 'ohmydebn-launch-tiled \K[0-9 ]+(?= -- )' "$REPO_ROOT/bin/$SCRIPT")
  check_tile_grid "$LABEL" "$GRID" "$SCRIPT's grid"
done

echo
echo "-- ohmydebn-terminal-tiled and ohmydebn-launch-tiled both delegate to ohmydebn-gtile-apply (regression guard) --"
# Guards against either script's tiling call getting inlined back into a
# second copy instead of going through the shared helper above - that's
# exactly the duplication this helper was extracted to avoid.
for TILED_SCRIPT in ohmydebn-terminal-tiled ohmydebn-launch-tiled; do
  # Anchored to an actual invocation (line starts with the path, after
  # only whitespace) rather than a bare substring match, so a comment
  # mentioning the helper's name can't make a since-removed real call
  # look like it's still there.
  if ! grep -qE '^\s*/usr/share/ohmydebn/bin/ohmydebn-gtile-apply\b' "$REPO_ROOT/bin/$TILED_SCRIPT"; then
    echo "  FAIL - $TILED_SCRIPT doesn't call ohmydebn-gtile-apply"
    FAIL=$((FAIL + 1))
  else
    echo "  $TILED_SCRIPT calls ohmydebn-gtile-apply"
  fi
done

echo
echo "-- OHMYDEBN_TILE_GRID launchers delegate to ohmydebn-terminal-tiled (regression guard) --"
# Guards against the launch-and-track-by-PID logic getting duplicated
# instead of reused via OHMYDEBN_TILE_GRID - exactly why that override
# exists.
for ENTRY in "${GRID_OVERRIDE_LAUNCHERS[@]}"; do
  GRID_LAUNCHER="${ENTRY%%:*}"
  if ! grep -qE '^\s*(exec )?/usr/share/ohmydebn/bin/ohmydebn-terminal-tiled\b' "$REPO_ROOT/bin/$GRID_LAUNCHER"; then
    echo "  FAIL - $GRID_LAUNCHER doesn't call ohmydebn-terminal-tiled"
    FAIL=$((FAIL + 1))
  else
    echo "  $GRID_LAUNCHER calls ohmydebn-terminal-tiled"
  fi
done

echo
echo "-- ohmydebn-launch-tiled-based launchers delegate to ohmydebn-launch-tiled (regression guard) --"
# Guards against the launch-then-poll-for-focus-change logic getting
# duplicated instead of reused - exactly why ohmydebn-launch-tiled exists.
for ENTRY in "${LAUNCH_TILED_LAUNCHERS[@]}"; do
  LAUNCH_TILED_LAUNCHER="${ENTRY%%:*}"
  if ! grep -qE '^\s*(exec )?/usr/share/ohmydebn/bin/ohmydebn-launch-tiled\b' "$REPO_ROOT/bin/$LAUNCH_TILED_LAUNCHER"; then
    echo "  FAIL - $LAUNCH_TILED_LAUNCHER doesn't call ohmydebn-launch-tiled"
    FAIL=$((FAIL + 1))
  else
    echo "  $LAUNCH_TILED_LAUNCHER calls ohmydebn-launch-tiled"
  fi
done

echo
echo "-- dpkg-gated launchers opt into OHMYDEBN_LAUNCH_TILED_WATCH_SECOND (regression guard) --"
# ohmydebn-cliamp/-socrates/-claude-code/-opencode/-pi were collapsed
# into a single terminal window for their whole lifecycle
# (install-if-needed, then run - see ohmydebn-cliamp's own comment), so
# their *-tiled wrappers no longer need this. ohmydebn-antigravity-tiled
# and ohmydebn-ai-tiled (which can also dispatch to ohmydebn-antigravity,
# among others) still do: ohmydebn-antigravity launches a native GUI
# binary as its second phase rather than running inside a terminal -
# that second window can't be collapsed away the same way, so it still
# needs ohmydebn-launch-tiled's own comment on this variable to apply.
# Must export the flag, or that second window silently never gets tiled
# once installation finishes (exactly the bug this variable exists to
# fix, first reported live for cliamp before it was collapsed away
# instead).
WATCH_SECOND_LAUNCHERS=(ohmydebn-ai-tiled ohmydebn-antigravity-tiled ohmydebn-code-tiled ohmydebn-chatgpt-tiled)
for WATCH_SECOND_LAUNCHER in "${WATCH_SECOND_LAUNCHERS[@]}"; do
  if ! grep -qE '^\s*export OHMYDEBN_LAUNCH_TILED_WATCH_SECOND=1\s*$' "$REPO_ROOT/bin/$WATCH_SECOND_LAUNCHER"; then
    echo "  FAIL - $WATCH_SECOND_LAUNCHER doesn't export OHMYDEBN_LAUNCH_TILED_WATCH_SECOND=1"
    FAIL=$((FAIL + 1))
  else
    echo "  $WATCH_SECOND_LAUNCHER exports OHMYDEBN_LAUNCH_TILED_WATCH_SECOND=1"
  fi
done

echo
echo "-- menu entries stay in sync with their equivalent hotkey's launcher (regression guard) --"
# Some apps are reachable both via a keybinding-custom.txt hotkey and an
# ohmydebn-menu case arm - when the hotkey gets rewired to a *-tiled
# launcher, the menu arm needs the same rewiring, or picking it from the
# menu silently falls back to the untiled behavior (this is exactly what
# happened to cliamp and ohmydebn-update-gui before both call sites were
# fixed together). Curated (not derived by scanning every hotkey/menu
# pair), since not every dual-reachable app is meant to tile the same way
# from both paths - adding a pair here asserts a real decision, not just
# whatever the menu happened to do.
# Each entry: "keybinding label:menu function:menu case keyword"
MENU_HOTKEY_PAIRS=(
  "cliamp:show_media_menu:cliamp"
  "ohmydebn-update:show_update_menu:OhMyDebn"
  "SO-CRATES:show_cybersecurity_menu:SO-CRATES"
  "Claude Code:show_ai_menu:Claude"
  "fastfetch:go_to_menu:about"
  "Antigravity:show_ai_menu:Antigravity"
  "Antigravity:show_editor_menu:Antigravity"
  "Visual Studio Code:show_ai_menu:VSCode"
  "Visual Studio Code:show_editor_menu:VSCode"
  "Cava:show_media_menu:Cava"
)
for ENTRY in "${MENU_HOTKEY_PAIRS[@]}"; do
  IFS=':' read -r KB_LABEL MENU_FUNC MENU_KEYWORD <<<"$ENTRY"
  KB_COMMAND=$(grep "\"$KB_LABEL\"" "$REPO_ROOT/install/keybinding/keybinding-custom.txt" | awk -F'"' '{print $4}')
  FUNC_START=$(grep -n "^${MENU_FUNC}()" "$MENU_FILE" | head -1 | cut -d: -f1)
  FUNC_END_REL=$(tail -n "+$FUNC_START" "$MENU_FILE" | grep -n '^}' | head -1 | cut -d: -f1)
  FUNC_END=$((FUNC_START + FUNC_END_REL - 1))
  MENU_ARM=$(sed -n "${FUNC_START},${FUNC_END}p" "$MENU_FILE" | grep -P "\*${MENU_KEYWORD}\*\)" |
    sed -E 's/^[[:space:]]*\*[^*]*\*\)[[:space:]]*//; s/[[:space:]]*;;[[:space:]]*$//')
  # A menu arm may run a side-effecting command first (e.g. the AI
  # submenu's ohmydebn-ai-set-default) before the actual launch - only
  # the final ";"-separated statement is the one that has to match the
  # hotkey's launcher.
  MENU_COMMAND="${MENU_ARM##*; }"
  if [[ -z "$KB_COMMAND" || -z "$MENU_COMMAND" ]]; then
    echo "  FAIL - couldn't find both a keybinding command for \"$KB_LABEL\" and a menu command for $MENU_FUNC's *${MENU_KEYWORD}*"
    FAIL=$((FAIL + 1))
  elif [[ "$KB_COMMAND" != "$MENU_COMMAND" ]]; then
    echo "  FAIL - hotkey \"$KB_LABEL\" ($KB_COMMAND) and menu $MENU_FUNC's *${MENU_KEYWORD}* ($MENU_COMMAND) launch different commands"
    FAIL=$((FAIL + 1))
  else
    echo "  \"$KB_LABEL\" hotkey and $MENU_FUNC's *${MENU_KEYWORD}* menu entry agree: $KB_COMMAND"
  fi
done

echo
echo "-- ohmydebn-menu captures OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN before the picker exists (regression guard) --"
# Must run before start_persistent_picker's own invocation (not its
# function definition further up the file), not from inside menu() - see
# the assignment's own comment for why: capturing "the active window"
# from inside menu() would grab the picker itself, which is already
# redundant with ohmydebn-launch-tiled's own PREV_WIN capture (see that
# script's comment) rather than the window that actually needs excluding
# (whatever was active before the picker ever appeared). Confirmed live:
# capturing inside menu() was exactly the first, wrong attempt at this.
EXCLUDE_ASSIGN_LINE=$(grep -n '^OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN=' "$MENU_FILE" | head -1 | cut -d: -f1)
PICKER_START_CALL_LINE=$(grep -n '^start_persistent_picker ||' "$MENU_FILE" | head -1 | cut -d: -f1)
MENU_FUNC_START_LINE=$(grep -n '^menu() {' "$MENU_FILE" | head -1 | cut -d: -f1)
MENU_FUNC_END_REL=$(tail -n "+$MENU_FUNC_START_LINE" "$MENU_FILE" | grep -n '^}' | head -1 | cut -d: -f1)
MENU_FUNC_END_LINE=$((MENU_FUNC_START_LINE + MENU_FUNC_END_REL - 1))
if [[ -z "$EXCLUDE_ASSIGN_LINE" || -z "$PICKER_START_CALL_LINE" ]]; then
  echo "  FAIL - couldn't find both the OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN assignment and the start_persistent_picker call"
  FAIL=$((FAIL + 1))
elif [[ "$EXCLUDE_ASSIGN_LINE" -ge "$PICKER_START_CALL_LINE" ]]; then
  echo "  FAIL - OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN (line $EXCLUDE_ASSIGN_LINE) isn't captured before start_persistent_picker (line $PICKER_START_CALL_LINE)"
  FAIL=$((FAIL + 1))
elif [[ "$EXCLUDE_ASSIGN_LINE" -ge "$MENU_FUNC_START_LINE" && "$EXCLUDE_ASSIGN_LINE" -le "$MENU_FUNC_END_LINE" ]]; then
  echo "  FAIL - OHMYDEBN_LAUNCH_TILED_EXCLUDE_WIN (line $EXCLUDE_ASSIGN_LINE) is captured from inside menu() ($MENU_FUNC_START_LINE-$MENU_FUNC_END_LINE) - that grabs the picker, not the pre-picker window"
  FAIL=$((FAIL + 1))
else
  echo "  captured at line $EXCLUDE_ASSIGN_LINE, before start_persistent_picker (line $PICKER_START_CALL_LINE) and outside menu() (line $MENU_FUNC_START_LINE-$MENU_FUNC_END_LINE)"
fi

echo
echo "-- every third-party apt repo is pinned to its own package(s) (regression guard) --"
# A bare `signed-by` trusts a repo's key to sign anything at all - without
# an apt-preferences pin scoping the repo to the specific package(s) it's
# actually needed for, a compromised or malicious upstream could ship a
# package under some other name (colliding with a real Debian package,
# say) and have apt prefer it on some later, completely unrelated
# `apt install`/upgrade, on any machine that ever ran this one installer.
# Confirmed live (via apt-cache policy against a scratch
# Dir::Etc::PreferencesParts, and by fetching each repo's real Packages
# file into a scratch apt state to check dependencies) that every
# existing third-party-repo installer got exactly this pin when the
# pattern was added - this guards the next new one from skipping it.
# Matched by the write itself (tee/curl -o onto sources.list.d), not a
# mere existence check - ohmydebn-boxes-install/ohmydebn-virtmanager-
# install both test `[ -f .../proxmox.sources ]` without ever adding a
# repo of their own, and must NOT be flagged here.
mapfile -t REPO_ADDING_SCRIPTS < <(grep -lP '\b(tee|curl)\b[^\n]*(-o\s+|>\s*)?/etc/apt/sources\.list\.d/' "$REPO_ROOT"/bin/*-install 2>/dev/null)
CHECKED=0
for f in "${REPO_ADDING_SCRIPTS[@]}"; do
  CHECKED=$((CHECKED + 1))
  if ! grep -q 'preferences\.d' "$f"; then
    echo "  FAIL - ${f#"$REPO_ROOT"/} adds a third-party apt repo but never pins it to specific package(s) via /etc/apt/preferences.d"
    FAIL=$((FAIL + 1))
  fi
done
echo "  checked $CHECKED third-party-repo installers"

echo
echo "$FAIL failure(s)"
[[ $FAIL -eq 0 ]]
