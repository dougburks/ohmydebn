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
# power-user.sh is currently the only automation that relies on
# --skip-prompt. If a future file adds more of these calls, extend the
# extraction below to match.

echo
echo "-- --skip-prompt consistency (install/packaging/power-user.sh) --"
SKIP_PROMPT_NAMES=()
mapfile -t LOOP_NAMES < <(sed -n '/^  for SCRIPT in/,/; do/{p; /; do/q}' "$POWER_USER_SH" |
  sed '1s/^  for SCRIPT in //; s/; do$//; s/\\$//' | tr -s ' \t' '\n' | grep -v '^\s*$')
SKIP_PROMPT_NAMES+=("${LOOP_NAMES[@]}")
if grep -q 'ohmydebn-pkg-remove-all-optional --skip-prompt' "$POWER_USER_SH"; then
  SKIP_PROMPT_NAMES+=("ohmydebn-pkg-remove-all-optional")
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
# ohmydebn-menu has two different case-statement styles: `case $(menu "Title"
# "items") in ...` (dispatches on a displayed selection - checked here) and
# `case "${1,,}" in ...` in go_to_menu() (dispatches on a CLI argument, not
# a menu selection - deliberately not covered by this check). Scoped per
# block (not a whole-file keyword pool) so a keyword from one menu can't
# spuriously "match" unrelated text in a different menu elsewhere in the file.

echo
echo "-- ohmydebn-menu case-arm consistency --"
MENU_FILE="$REPO_ROOT/bin/ohmydebn-menu"
CHECKED=0
mapfile -t BLOCK_STARTS < <(grep -n 'case \$(menu "' "$MENU_FILE" | cut -d: -f1)
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
#              picker/-theme-carousel/-theme-bg-carousel work that replaced
#              every real rofi call site this project had --

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
  "$REPO_ROOT/bin/ohmydebn-menu-picker" "$REPO_ROOT/bin/ohmydebn-theme-carousel" \
  "$REPO_ROOT/bin/ohmydebn-theme-bg-carousel" 2>/dev/null)
for f in "${SCALE_HITS[@]}"; do
  echo "  FAIL - ${f#"$REPO_ROOT"/} references a manual scale-query mechanism - GTK already scales set_default_size()/fullscreen() automatically"
  FAIL=$((FAIL + 1))
done
echo "  checked the 3 GTK pickers for manual scale pre-multiplication"

echo
echo "$FAIL failure(s)"
[[ $FAIL -eq 0 ]]
