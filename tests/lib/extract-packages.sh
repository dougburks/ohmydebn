#!/bin/bash
#
# extract-packages.sh: Shared helpers for pulling package name lists out of
# the repo's own package-management scripts. Sourced by both apt-checks.sh
# and consistency.sh so the two don't drift out of sync on how they parse
# these files. Depends on these variables being set by the caller:
#   DEPENDENCIES_SH, POWER_USER_SH, REMOVE_ALL_SH, BUILD_SCRIPT

# Package names from dependencies.sh's PACKAGES=( ... ) array.
extract_dependencies_sh_packages() {
  sed -n '/^PACKAGES=(/,/^)/p' "$DEPENDENCIES_SH" |
    grep -v '^PACKAGES=(\|^)' | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^\s*$'
}

# Package names passed to ohmydebn-pkg-install-optional in power-user.sh
# (spans a couple of continuation lines, ends at the trailing `||`).
extract_power_user_sh_packages() {
  awk '/ohmydebn-pkg-install-optional/{p=1} p{print} p && /\|\|/{p=0}' "$POWER_USER_SH" |
    sed 's#.*/ohmydebn-pkg-install-optional##; s/||.*//; s/\\$//' |
    tr -s ' \t' '\n' | grep -v '^\s*$'
}

# Package names purged by the main loop in ohmydebn-pkg-remove-all-optional
# (the "for PACKAGE in ... ; do" list before "; do"). The file has a SECOND
# "for PACKAGE in ...; do" loop further down (the dedicated-remove-script
# loop), so the sed range must stop (`q`) at the first "; do" match rather
# than running until the last one in the file.
extract_removal_packages() {
  sed -n '/^for PACKAGE in/,/; do/{p; /; do/q}' "$REMOVE_ALL_SH" |
    sed '1s/^for PACKAGE in //; s/; do$//; s/\\$//' |
    tr -s ' \t' '\n' | sed 's/^"//; s/"$//' | grep -v '^\s*$'
}

# Category A hard --depends packages from the sibling fpm build repo, if present.
extract_fpm_hard_depends() {
  [[ -f "$BUILD_SCRIPT" ]] || return 0
  grep -oP '(?<=--depends )\S+' "$BUILD_SCRIPT"
}
