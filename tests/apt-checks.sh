#!/bin/bash
#
# apt-checks.sh: Tier 3 - read-only, non-destructive checks against the
# real system's apt database. Nothing here installs, removes, or purges
# anything; it only queries (apt-cache show/depends, dpkg -l). Requires a
# Debian-family machine with an apt cache, but no disposable VM/container.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # consumed by the functions in extract-packages.sh, sourced below
DEPENDENCIES_SH="$REPO_ROOT/install/packaging/dependencies.sh"
# shellcheck disable=SC2034
POWER_USER_SH="$REPO_ROOT/install/packaging/power-user.sh"
# shellcheck disable=SC2034
REMOVE_ALL_SH="$REPO_ROOT/bin/ohmydebn-pkg-remove-all-optional"
# shellcheck disable=SC2034
BUILD_SCRIPT="$HOME/git/ohmydebn-package-build/build-package-ohmydebn.sh"

FAIL=0

echo "=== apt-checks ==="

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "apt-cache not available - skipping (not a Debian-family system)"
  exit 0
fi

source "$REPO_ROOT/tests/lib/extract-packages.sh"

# --- check 1: every referenced package name actually exists -----------

echo
echo "-- package existence --"

mapfile -t OHMYDEBN_OWNED < <(extract_fpm_hard_depends | grep -E '^(ohmydebn-|mint-|ttfx$|toilet$|toilet-fonts$|screenfetch$)')

check_packages_exist() {
  local label="$1"
  shift
  local pkg
  for pkg in "$@"; do
    [[ -z "$pkg" ]] && continue
    if apt-cache show "$pkg" >/dev/null 2>&1; then
      continue
    fi
    if printf '%s\n' "${OHMYDEBN_OWNED[@]}" | grep -qxF "$pkg"; then
      echo "  info - $label: '$pkg' not found (comes from ohmydebn's own repo - only relevant if that repo isn't configured on this machine)"
    else
      echo "  FAIL - $label: '$pkg' not found in any configured apt source"
      FAIL=$((FAIL + 1))
    fi
  done
}

mapfile -t DEP_PKGS < <(extract_dependencies_sh_packages)
mapfile -t POWERUSER_PKGS < <(extract_power_user_sh_packages)
mapfile -t FPM_PKGS < <(extract_fpm_hard_depends)

check_packages_exist "dependencies.sh" "${DEP_PKGS[@]}"
check_packages_exist "power-user.sh" "${POWERUSER_PKGS[@]}"
check_packages_exist "build-package-ohmydebn.sh (Category A)" "${FPM_PKGS[@]}"

echo "checked ${#DEP_PKGS[@]} + ${#POWERUSER_PKGS[@]} + ${#FPM_PKGS[@]} package names"

# --- check 2: alternative-dependency safety ----------------------------
#
# Regression guard for the exact bug found in this repo: cinnamon-desktop-
# environment hard-depends on "gnome-calculator | galculator" (an
# alternative - either satisfies it). Purging gnome-calculator (an
# ohmydebn-pkg-remove-all-optional target) while galculator wasn't
# installed yet briefly left that dependency unsatisfied. This checks
# every "A | B" alternative group in cinnamon-desktop-environment's real
# Depends: field: if A is something we remove, B must be something we
# install, so the swap is always safe.

echo
echo "-- alternative-dependency safety (cinnamon-desktop-environment) --"

if apt-cache show cinnamon-desktop-environment >/dev/null 2>&1; then
  mapfile -t REMOVED < <(extract_removal_packages)
  mapfile -t INSTALLED < <(extract_dependencies_sh_packages; extract_power_user_sh_packages)

  DEPENDS_FIELD=$(apt-cache show cinnamon-desktop-environment | grep "^Depends:" | head -1 | sed 's/^Depends: //')
  # Note: NOT named GROUPS - that's a bash builtin special array (the
  # current user's UNIX group IDs) and silently collides with it.
  IFS=',' read -ra DEPEND_GROUPS <<<"$DEPENDS_FIELD"
  for group in "${DEPEND_GROUPS[@]}"; do
    [[ "$group" != *"|"* ]] && continue
    IFS='|' read -ra ALTS <<<"$group"
    # Strip version constraints like "(>= 1.2)" and whitespace.
    for i in "${!ALTS[@]}"; do
      ALTS[$i]=$(echo "${ALTS[$i]}" | sed 's/([^)]*)//g' | xargs)
    done

    removed_alt=""
    for alt in "${ALTS[@]}"; do
      if printf '%s\n' "${REMOVED[@]}" | grep -qxF "$alt"; then
        removed_alt="$alt"
        break
      fi
    done
    [[ -z "$removed_alt" ]] && continue

    other_installed=false
    for alt in "${ALTS[@]}"; do
      [[ "$alt" == "$removed_alt" ]] && continue
      if printf '%s\n' "${INSTALLED[@]}" | grep -qxF "$alt"; then
        other_installed=true
        break
      fi
    done

    if [[ "$other_installed" == true ]]; then
      echo "  ok - '$removed_alt' is removed, but an alternative in its group (${ALTS[*]}) is installed"
    else
      echo "  FAIL - '$removed_alt' is removed, but no alternative in its group (${ALTS[*]}) is installed anywhere - purging it would break cinnamon-desktop-environment's dependency"
      FAIL=$((FAIL + 1))
    fi
  done
else
  echo "  cinnamon-desktop-environment not found in apt cache - skipping (ohmydebn's target repos not configured on this machine)"
fi

echo
echo "$FAIL failure(s)"
[[ $FAIL -eq 0 ]]
