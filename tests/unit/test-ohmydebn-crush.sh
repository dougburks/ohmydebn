#!/bin/bash
#
# Unit tests for Crush, Charm's terminal coding agent: bin/ohmydebn-crush
# (the launcher), -run, -cli, -install and -remove. Crush comes from
# Charm's signed apt repository, pinned to crush alone, since the
# repository carries all of Charm's tools (OhMyDebn ships its own gum). If
# Charm's repository is already set up (Charm's own instructions add it as
# charm.list for gum, glow...), Crush comes from that, and OhMyDebn adds no
# second source and no pin that would hold the other tools back. The key
# check itself is covered in test-vendor-key-fingerprints.sh.
#
# /etc/apt and /usr/share/keyrings are sed-patched to a scratch root; sudo
# runs its command for real against those paths except apt, which is only
# logged (MOCK_APT_UPDATE_FAILS fails apt update; apt install marks crush
# installed); curl serves Charm's real public key from tests/lib; gpg
# --dearmor copies its input; dpkg answers from that install marker or
# MOCK_INSTALLED.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-crush, -run, -cli, -install, -remove ==="

setup() {
  mock_init
  ROOT="$MOCK_DIR/root"
  APT="$ROOT/etc/apt"
  mkdir -p "$APT/sources.list.d" "$APT/preferences.d" "$ROOT/usr/share/keyrings" "$MOCK_DIR/home"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && ( -f "$MOCK_DIR/installed" || " ${MOCK_INSTALLED:-} " == *" $2 "* ) ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
if [[ "$1" == /usr/bin/apt ]]; then
  [[ "$*" == "/usr/bin/apt update" && -n "${MOCK_APT_UPDATE_FAILS:-}" ]] && exit 100
  [[ "$*" == "/usr/bin/apt -y install crush" ]] && touch "$MOCK_DIR/installed"
  exit 0
fi
exec "$@"
EOF2
  mock_bin curl <<'EOF2'
#!/bin/bash
mock_log "curl $*"
cp "$REPO_ROOT/tests/lib/charm-signing-key.asc" "${!#}"
EOF2
  mock_bin gpg <<'EOF2'
#!/bin/bash
while [ $# -gt 1 ]; do
  case "$1" in -o | --output) dest="$2"; shift ;; esac
  shift
done
cp "$1" "$dest"
EOF2
  mock_bin crush <<'EOF2'
#!/bin/bash
mock_log "crush${*:+ $*} in ${PWD/#"$HOME"/"~"}"
EOF2
  for stub in ohmydebn-show-logo ohmydebn-show-done ohmydebn-terminal ohmydebn-ai-set-default; do
    printf '#!/bin/bash\nmock_log "%s${*:+ $*}"\n' "$stub" | mock_bin "$stub"
  done
  cp "$REPO_ROOT/bin/ohmydebn-pgp-fingerprint" "$MOCK_BIN/"
  for script in ohmydebn-crush ohmydebn-crush-run ohmydebn-crush-cli ohmydebn-crush-install ohmydebn-crush-remove; do
    sed -e "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" -e "s#/usr/bin/crush#$MOCK_BIN/crush#g" \
      -e "s#/usr/share/keyrings#$ROOT/usr/share/keyrings#g" -e "s#/etc/apt#$APT#g" \
      "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
}

# run <script> [stdin] [args...]
run() {
  local script="$1" input="${2:-}"
  shift 2 2>/dev/null || shift
  OUTPUT=$(HOME="$MOCK_DIR/home" REPO_ROOT="$REPO_ROOT" PATH="$(mock_path)" bash "$MOCK_BIN/$script" "$@" <<<"$input" 2>&1)
  STATUS=$?
  CALLS=$(cat "$MOCK_CALLS")
}

exists() { [[ -e "$1" ]] && echo yes || echo no; }

# --- the launcher: one titled terminal running the payload ---
setup
run ohmydebn-crush
assert_eq "launcher: a terminal titled Crush (its tile rule's title), running the payload" \
  "ohmydebn-terminal --title Crush -e $MOCK_BIN/ohmydebn-crush-run" "$CALLS"
mock_cleanup

# --- first install: Charm's key, a source of OhMyDebn's own, pinned to crush ---
setup
run ohmydebn-crush-install $'\n'
assert_eq "install: exits 0" "0" "$STATUS"
assert_contains "install: asks before changing anything" "$OUTPUT" "Press Enter to continue or Ctrl-C to cancel."
assert_contains "install: the key comes from Charm" "$CALLS" "curl -fsSL https://repo.charm.sh/apt/gpg.key"
assert_eq "install: the source, as Charm's documented line in deb822" "Types: deb
URIs: https://repo.charm.sh/apt/
Suites: *
Components: *
Signed-By: /usr/share/keyrings/charm-crush.gpg" "$(sed "s#$ROOT##" "$APT/sources.list.d/charm-crush.sources")"
assert_eq "install: the pin lets nothing but crush come from Charm's repo" "Package: *
Pin: origin \"repo.charm.sh\"
Pin-Priority: -1

Package: crush
Pin: origin \"repo.charm.sh\"
Pin-Priority: 500" "$(cat "$APT/preferences.d/charm-crush.pref")"
assert_eq "install: the pin is in place before apt update" "yes" \
  "$(grep -n 'charm-crush.pref\|apt update' "$MOCK_CALLS" | head -1 | grep -q pref && echo yes || echo no)"
assert_contains "install: installs crush" "$CALLS" "sudo /usr/bin/apt -y install crush"
assert_contains "install: asks whether to make it the default" "$CALLS" "ohmydebn-ai-set-default --ask crush"
mock_cleanup

# --- Charm's repository already set up (charm.list, from Charm's own
# instructions): used as it is, with no second source and no pin ---
setup
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" >"$APT/sources.list.d/charm.list"
run ohmydebn-crush-install $'\n'
assert_eq "Charm's repo already there: exits 0" "0" "$STATUS"
assert_contains "Charm's repo already there: says so" "$OUTPUT" "already configured on this system - using it"
assert_not_contains "Charm's repo already there: no key downloaded" "$CALLS" "curl"
assert_eq "Charm's repo already there: no source of OhMyDebn's" "no" "$(exists "$APT/sources.list.d/charm-crush.sources")"
assert_eq "Charm's repo already there: no pin holding back Charm's other tools" "no" "$(exists "$APT/preferences.d/charm-crush.pref")"
assert_contains "Charm's repo already there: installs crush from it" "$CALLS" "sudo /usr/bin/apt -y install crush"
mock_cleanup

# --- apt can't refresh: OhMyDebn's source is taken out again ---
setup
MOCK_APT_UPDATE_FAILS=1 run ohmydebn-crush-install $'\n'
assert_eq "apt update fails: fails" "1" "$STATUS"
assert_eq "apt update fails: source removed again" "no" "$(exists "$APT/sources.list.d/charm-crush.sources")"
assert_eq "apt update fails: pin removed again" "no" "$(exists "$APT/preferences.d/charm-crush.pref")"
assert_eq "apt update fails: key removed again" "no" "$(exists "$ROOT/usr/share/keyrings/charm-crush.gpg")"
assert_not_contains "apt update fails: nothing installed" "$CALLS" "apt -y install"
mock_cleanup
setup
echo "deb https://repo.charm.sh/apt/ * *" >"$APT/sources.list.d/charm.list"
MOCK_APT_UPDATE_FAILS=1 run ohmydebn-crush-install $'\n'
assert_eq "apt update fails, Charm's repo the user's: left alone" "yes" "$(exists "$APT/sources.list.d/charm.list")"
mock_cleanup

# --- --skip-prompt: asks nothing ---
setup
run ohmydebn-crush-install "" --skip-prompt
assert_eq "--skip-prompt: exits 0" "0" "$STATUS"
assert_not_contains "--skip-prompt: no Enter prompt" "$OUTPUT" "Press Enter"
assert_not_contains "--skip-prompt: no default-agent question" "$CALLS" "ohmydebn-ai-set-default"
mock_cleanup

# --- already installed: nothing to do ---
setup
MOCK_INSTALLED=crush run ohmydebn-crush-install
assert_eq "installed: installer does nothing" "" "$CALLS"
mock_cleanup

# --- the run payload: installs on first use, then runs in a fresh session folder ---
setup
run ohmydebn-crush-run $'\n'
assert_eq "first use: exits 0" "0" "$STATUS"
assert_contains "first use: installs crush" "$CALLS" "sudo /usr/bin/apt -y install crush"
assert_eq "first use: then runs it in a new ~/crush-sessions folder" "yes" \
  "$(tail -1 "$MOCK_CALLS" | grep -qE '^crush in ~/crush-sessions/session-[A-Za-z0-9]{6}$' && echo yes || echo no)"
mock_cleanup
setup
MOCK_INSTALLED=crush run ohmydebn-crush-run
assert_eq "installed: just runs it" "yes" \
  "$(grep -qE '^crush in ~/crush-sessions/session-' <<<"$CALLS" && [ "$(wc -l <<<"$CALLS")" = 1 ] && echo yes || echo no)"
mock_cleanup

# --- the -cli companion: runs in the current folder, passing its arguments ---
setup
MOCK_INSTALLED=crush run ohmydebn-crush-cli "" run "fix the tests"
assert_eq "cli: passes its arguments, in the current folder" "crush run fix the tests in $PWD" "$CALLS"
mock_cleanup

# --- remove: only OhMyDebn's own files go ---
setup
: >"$APT/sources.list.d/charm-crush.sources"
: >"$APT/preferences.d/charm-crush.pref"
: >"$ROOT/usr/share/keyrings/charm-crush.gpg"
echo "deb https://repo.charm.sh/apt/ * *" >"$APT/sources.list.d/charm.list"
MOCK_INSTALLED=crush run ohmydebn-crush-remove $'\n'
assert_eq "remove: exits 0" "0" "$STATUS"
assert_contains "remove: says settings are kept" "$OUTPUT" "are kept."
assert_eq "remove: OhMyDebn's source goes" "no" "$(exists "$APT/sources.list.d/charm-crush.sources")"
assert_eq "remove: its pin goes" "no" "$(exists "$APT/preferences.d/charm-crush.pref")"
assert_eq "remove: its key goes" "no" "$(exists "$ROOT/usr/share/keyrings/charm-crush.gpg")"
assert_eq "remove: a charm.list of the user's stays" "yes" "$(exists "$APT/sources.list.d/charm.list")"
assert_contains "remove: purges crush" "$CALLS" "sudo /usr/bin/apt -y purge crush"
mock_cleanup
setup
run ohmydebn-crush-remove
assert_contains "remove, not installed: says so" "$OUTPUT" "Crush is not currently installed."
assert_eq "remove, not installed: does nothing" "" "$CALLS"
mock_cleanup

test_summary
