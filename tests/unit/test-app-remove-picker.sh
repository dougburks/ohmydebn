#!/bin/bash
#
# Unit tests for the pickers in bin/ohmydebn-webapp-remove and
# bin/ohmydebn-tui-remove. Both sorted the launchers they found with
# sort <<<"${ARR[*]}", which joins every name onto one line: with two or more
# web apps (or TUIs) the picker offered one entry naming them all, choosing
# it removed nothing, and the script still printed "Removed". gum is stubbed
# to record each option it's offered and to choose all of them.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-webapp-remove and ohmydebn-tui-remove pickers ==="

mock_init
mock_bin gum <<'EOF2'
#!/bin/bash
# gum choose [--flags...] option...: every option, one per line, both as
# offered and as chosen.
[[ "$1" == "choose" ]] || exit 0
shift
while (($#)); do
  case "$1" in
  --header) shift 2 ;;
  --*) shift ;;
  *)
    mock_log "offered: $1"
    echo "$1"
    shift
    ;;
  esac
done
EOF2

# make_launcher <name> <Exec line>
make_launcher() {
  cat >"$SCRATCH_HOME/.local/share/applications/$1.desktop" <<EOF2
[Desktop Entry]
Exec=$2
EOF2
  touch "$SCRATCH_HOME/.local/share/applications/icons/$1.png"
}

# check <script> <Exec line> <kind>
check() {
  local script="$1" exec="$2" kind="$3" out
  SCRATCH_HOME=$(mktemp -d)
  mkdir -p "$SCRATCH_HOME/.local/share/applications/icons"
  : >"$MOCK_CALLS"
  make_launcher "Beta App" "$exec"
  make_launcher "Alpha" "$exec"
  out=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$REPO_ROOT/bin/$script" </dev/null 2>&1)
  assert_eq "$kind: each launcher is its own entry, sorted" \
    "$(printf 'offered: Alpha\noffered: Beta App')" "$(cat "$MOCK_CALLS")"
  assert_eq "$kind: choosing both removes both" "" \
    "$(find "$SCRATCH_HOME/.local/share/applications" -name '*.desktop' -o -name '*.png')"
  assert_contains "$kind: reports what it removed" "$out" "Removed Beta App"

  out=$(HOME="$SCRATCH_HOME" bash "$REPO_ROOT/bin/$script" "Gamma" </dev/null 2>&1)
  assert_not_contains "$kind: a name with no launcher isn't reported removed" "$out" "Removed"
  rm -rf "$SCRATCH_HOME"
}

check ohmydebn-webapp-remove "ohmydebn-launch-webapp https://example.com" "web apps"
check ohmydebn-tui-remove "ohmydebn-terminal -e btop" "TUIs"

mock_cleanup
test_summary
