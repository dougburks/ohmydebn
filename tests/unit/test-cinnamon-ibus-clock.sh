#!/bin/bash
#
# Unit tests for the ibus-panel and clock-format blocks in
# install/config/cinnamon.sh. On Kali (which defaults to XFCE, not
# Cinnamon) ibus and its GSettings schema aren't installed - ohmydebn never
# installs ibus itself, it's only present by accident on the Debian
# Cinnamon ISO. `gsettings set org.freedesktop.ibus.panel ...` fails there
# with "No such schema". Since install.sh runs the whole install under
# `set -e`, an unguarded failure on that one line used to abort everything
# after it, including the clock-format block right below it. This guards
# the `|| true` fix that keeps that failure from taking the rest of the
# install down with it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/install/config/cinnamon.sh"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/config/cinnamon.sh (ibus-panel / clock-format) ==="

setup_mocks() {
  mock_bin ohmydebn-headline <<'EOF'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF
  # FAIL_IBUS=true simulates the missing-schema case seen on Kali/XFCE.
  mock_bin gsettings <<'EOF'
#!/bin/bash
mock_log "gsettings $*"
if [[ "${FAIL_IBUS:-}" == "true" && "$2" == "org.freedesktop.ibus.panel" ]]; then
  echo 'No such schema "org.freedesktop.ibus.panel"' >&2
  exit 1
fi
exit 0
EOF
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$SCRIPT" >"$MOCK_DIR/cinnamon-patched.sh"
}

# Pre-seed every state file the earlier blocks in cinnamon.sh gate on, so
# only the ibus-panel and clock-format blocks under test actually run (the
# earlier blocks cp from /usr/share/ohmydebn, which doesn't exist here).
seed_earlier_state() {
  mkdir -p "$SCRATCH_HOME/.local/state/ohmydebn-config"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-panel"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-panel-applet"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-window-speed"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-alttab"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-spices"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-config/gTile-config-20250920"
  touch "$SCRATCH_HOME/.local/state/ohmydebn-config/nemo-config-20250924"
}

# Scenario 1 (regression): ibus schema missing (Kali/XFCE) -> that
# gsettings call fails, but `|| true` keeps `set -e` (the real install.sh
# runs under it) from aborting before the clock-format block runs.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_earlier_state
FAIL_IBUS=true HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash -e "$MOCK_DIR/cinnamon-patched.sh" >/dev/null 2>&1
EXIT_CODE=$?
assert_eq "missing ibus schema: script still exits 0" "0" "$EXIT_CODE"
assert_eq "missing ibus schema: ibus state file still written" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/ibus-panel-20260828" ] && echo yes || echo no)"
assert_eq "missing ibus schema: clock-format block still ran" "yes" \
  "$([ -f "$SCRATCH_HOME/.local/state/ohmydebn-config/clock-format-20260828" ] && echo yes || echo no)"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "missing ibus schema: clock-format gsettings still called" "$CALLS" \
  "gsettings set org.cinnamon.desktop.interface clock-use-24h false"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: ibus schema present (normal Debian Cinnamon ISO) -> both
# settings applied, both state files written.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
seed_earlier_state
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash -e "$MOCK_DIR/cinnamon-patched.sh" >/dev/null 2>&1
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "ibus schema present: script exits 0" "0" "$EXIT_CODE"
assert_contains "ibus schema present: ibus gsettings called" "$CALLS" \
  "gsettings set org.freedesktop.ibus.panel show-icon-on-systray false"
assert_contains "ibus schema present: clock-format gsettings called" "$CALLS" \
  "gsettings set org.cinnamon.desktop.interface clock-use-24h false"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
