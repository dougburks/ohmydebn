#!/bin/bash
#
# Unit tests for bin/ohmydebn-brave-repo and the Brave Origin install/remove
# scripts built on it (Brave Browser's are the same template). The cases
# that matter came from LCOS, which ships Brave Origin from Brave's own
# repository via its own brave.list: no duplicate source may be added, the
# profile seed must still apply to a user who never ran it, and the remove
# script must refuse to purge a browser the distro installed.
#
# /etc/apt, /usr/share/keyrings, ~/.config and /usr/share/ohmydebn are all
# sed-patched to a scratch root; sudo runs its command for real against
# those paths except apt, which is only logged; curl writes a stub; dpkg
# answers from MOCK_INSTALLED.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-brave-repo / ohmydebn-brave-origin-install / -remove ==="

setup() {
  mock_init
  ROOT="$MOCK_DIR/root"; H="$MOCK_DIR/home"
  mkdir -p "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/preferences.d" "$ROOT/usr/share/keyrings" "$H" \
    "$ROOT/usr/share/ohmydebn/config/BraveSoftware/Brave-Origin/Default"
  echo '{"seed": true}' >"$ROOT/usr/share/ohmydebn/config/BraveSoftware/Brave-Origin/Default/Preferences"
  echo '{"local": true}' >"$ROOT/usr/share/ohmydebn/config/BraveSoftware/Brave-Origin/Local State"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
[[ "$1" == /usr/bin/apt ]] && exit 0
exec "$@"
EOF2
  mock_bin curl <<'EOF2'
#!/bin/bash
# curl -fsSLo <dest> <url>
mock_log "curl $*"
echo "stub from $3" >"$2"
EOF2
  for script in ohmydebn-brave-repo ohmydebn-brave-origin-install ohmydebn-brave-origin-remove; do
    sed "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g; s#^APT_ETC=/etc/apt#APT_ETC=$ROOT/etc/apt#; s#^KEYRING=/usr/share/keyrings#KEYRING=$ROOT/usr/share/keyrings#" \
      "$REPO_ROOT/bin/$script" >"$ROOT/usr/share/ohmydebn/bin-$script"
  done
  mkdir -p "$ROOT/usr/share/ohmydebn/bin"
  for script in ohmydebn-brave-repo ohmydebn-brave-origin-install ohmydebn-brave-origin-remove; do
    mv "$ROOT/usr/share/ohmydebn/bin-$script" "$ROOT/usr/share/ohmydebn/bin/$script"; chmod +x "$ROOT/usr/share/ohmydebn/bin/$script"
  done
  BIN="$ROOT/usr/share/ohmydebn/bin"
  OURS="$ROOT/etc/apt/sources.list.d/brave-browser-release.sources"
}
run() { HOME="$H" PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" bash "$@" </dev/null; }

# --- fresh Debian: nothing installed, no source -> repo added, package installed, profile seeded ---
setup
OUT=$(MOCK_INSTALLED="" run "$BIN/ohmydebn-brave-origin-install" --skip-prompt 2>&1)
assert_eq "fresh: our sources file written" "yes" "$([ -f "$OURS" ] && echo yes || echo no)"
assert_eq "fresh: pin written, restricting the repo to Brave's packages" "yes" "$(grep -q 'Package: brave-browser brave-origin brave-keyring' "$ROOT/etc/apt/preferences.d/brave-browser-release.pref" && echo yes || echo no)"
assert_eq "fresh: keyring fetched" "yes" "$([ -f "$ROOT/usr/share/keyrings/brave-browser-archive-keyring.gpg" ] && echo yes || echo no)"
assert_contains "fresh: package installed" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y install brave-origin"
# the package "arrives" during install: dpkg mock can't flip mid-run, so the seed is checked in the installed scenarios below
mock_cleanup

# --- LCOS: package present from Brave's repo via the distro's own brave.list, user never ran it ---
setup
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" >"$ROOT/etc/apt/sources.list.d/brave.list"
OUT=$(MOCK_INSTALLED="brave-origin" run "$BIN/ohmydebn-brave-origin-install" --skip-prompt 2>&1)
assert_eq "LCOS: no duplicate source added beside the distro's brave.list" "no" "$([ -e "$OURS" ] && echo yes || echo no)"
assert_eq "LCOS: no pin written either" "no" "$([ -e "$ROOT/etc/apt/preferences.d/brave-browser-release.pref" ] && echo yes || echo no)"
assert_not_contains "LCOS: nothing installed or fetched" "$(cat "$MOCK_CALLS")" "apt"
assert_eq "LCOS: profile seeded for a user who never ran Brave" '{"seed": true}' "$(cat "$H/.config/BraveSoftware/Brave-Origin/Default/Preferences" 2>/dev/null)"
assert_eq "LCOS: Local State seeded alongside the profile" '{"local": true}' "$(cat "$H/.config/BraveSoftware/Brave-Origin/Local State" 2>/dev/null)"
mock_cleanup

# --- installed with an existing profile: the profile is the user's, never overwritten ---
setup
echo "deb https://brave-browser-apt-release.s3.brave.com/ stable main" >"$ROOT/etc/apt/sources.list.d/brave.list"
mkdir -p "$H/.config/BraveSoftware/Brave-Origin/Default"; echo '{"mine": true}' >"$H/.config/BraveSoftware/Brave-Origin/Default/Preferences"
MOCK_INSTALLED="brave-origin" run "$BIN/ohmydebn-brave-origin-install" --skip-prompt >/dev/null 2>&1
assert_eq "existing profile: left untouched" '{"mine": true}' "$(cat "$H/.config/BraveSoftware/Brave-Origin/Default/Preferences")"
mock_cleanup

# --- installed from a bare .deb, no repository anywhere: add Brave's so it updates ---
setup
MOCK_INSTALLED="brave-origin" run "$BIN/ohmydebn-brave-origin-install" --skip-prompt >/dev/null 2>&1
assert_eq "bare .deb: our source added so the package receives updates" "yes" "$([ -f "$OURS" ] && echo yes || echo no)"
assert_not_contains "bare .deb: not reinstalled" "$(cat "$MOCK_CALLS")" "apt -y install"
mock_cleanup

# --- not installed, but a distro source already exists: install without adding a second source ---
setup
echo "deb https://brave-browser-apt-release.s3.brave.com/ stable main" >"$ROOT/etc/apt/sources.list.d/brave.list"
OUT=$(MOCK_INSTALLED="" run "$BIN/ohmydebn-brave-origin-install" --skip-prompt 2>&1)
assert_eq "distro source, not installed: no second source" "no" "$([ -e "$OURS" ] && echo yes || echo no)"
assert_contains "distro source, not installed: says the repo is already configured" "$OUT" "already configured"
assert_contains "distro source, not installed: still installs the package" "$(cat "$MOCK_CALLS")" "apt -y install brave-origin"
mock_cleanup

# --- remove: distro-installed (no OhMyDebn source) -> refuse, purge nothing ---
setup
echo "deb https://brave-browser-apt-release.s3.brave.com/ stable main" >"$ROOT/etc/apt/sources.list.d/brave.list"
OUT=$(MOCK_INSTALLED="brave-origin" run "$BIN/ohmydebn-brave-origin-remove" --skip-prompt 2>&1); STATUS=$?
assert_eq "remove (distro-owned): exits 0" "0" "$STATUS"
assert_contains "remove (distro-owned): explains and refuses" "$OUT" "installed by your distribution, not by OhMyDebn"
assert_not_contains "remove (distro-owned): no purge" "$(cat "$MOCK_CALLS")" "purge"
assert_eq "remove (distro-owned): the distro's source is untouched" "yes" "$([ -f "$ROOT/etc/apt/sources.list.d/brave.list" ] && echo yes || echo no)"
mock_cleanup

# --- remove: OhMyDebn-installed -> purge, and clean the repo files since Brave Browser isn't there ---
setup
: >"$OURS"; : >"$ROOT/etc/apt/preferences.d/brave-browser-release.pref"; : >"$ROOT/usr/share/keyrings/brave-browser-archive-keyring.gpg"
MOCK_INSTALLED="brave-origin" run "$BIN/ohmydebn-brave-origin-remove" --skip-prompt >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "remove (ours): purges the package" "$CALLS" "sudo /usr/bin/apt -y purge brave-origin"
assert_eq "remove (ours): our sources file removed" "no" "$([ -e "$OURS" ] && echo yes || echo no)"
assert_eq "remove (ours): our pin removed" "no" "$([ -e "$ROOT/etc/apt/preferences.d/brave-browser-release.pref" ] && echo yes || echo no)"
mock_cleanup

# --- remove: OhMyDebn-installed but Brave Browser also present -> repo files stay ---
setup
: >"$OURS"
MOCK_INSTALLED="brave-origin brave-browser" run "$BIN/ohmydebn-brave-origin-remove" --skip-prompt >/dev/null 2>&1
assert_contains "remove (both variants): still purges brave-origin" "$(cat "$MOCK_CALLS")" "purge brave-origin"
assert_eq "remove (both variants): shared repo files kept for brave-browser" "yes" "$([ -f "$OURS" ] && echo yes || echo no)"
mock_cleanup

# --- the helper's own verbs ---
setup
assert_eq "helper: is-configured false with no sources" "1" "$(run "$BIN/ohmydebn-brave-repo" is-configured >/dev/null 2>&1; echo $?)"
echo "URIs: https://brave-browser-apt-release.s3.brave.com" >"$ROOT/etc/apt/sources.list.d/whatever.sources"
assert_eq "helper: is-configured true when any source (deb822 too) names the host" "0" "$(run "$BIN/ohmydebn-brave-repo" is-configured >/dev/null 2>&1; echo $?)"
assert_eq "helper: is-ours false when only a foreign source exists" "1" "$(run "$BIN/ohmydebn-brave-repo" is-ours >/dev/null 2>&1; echo $?)"
assert_eq "helper: unknown verb exits 1 with usage" "1" "$(run "$BIN/ohmydebn-brave-repo" frobnicate >/dev/null 2>&1; echo $?)"
mock_cleanup

# --- the shipped seed itself: Brave Origin's free-tier acceptance is what keeps its first-launch dialog away ---
# (brave.origin.free_tier_accepted in Local State - the pref
# --skip-origin-startup-dialog persists; see ohmydebn-brave-origin-install)
assert_eq "shipped seed: Local State pre-accepts the Linux free tier" "True" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["brave"]["origin"]["free_tier_accepted"])' "$REPO_ROOT/config/BraveSoftware/Brave-Origin/Local State" 2>&1)"
assert_eq "shipped seed: Default/Preferences is valid JSON" "ok" \
  "$(python3 -c 'import json,sys; json.load(open(sys.argv[1])); print("ok")' "$REPO_ROOT/config/BraveSoftware/Brave-Origin/Default/Preferences" 2>&1)"

test_summary
