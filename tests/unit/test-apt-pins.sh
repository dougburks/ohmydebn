#!/bin/bash
#
# Unit tests for bin/ohmydebn-apt-pins. --list is the doctor's list of
# third-party repos and their pins. --prune cleans up after apps removed
# with Remove > Package or apt: a repo OhMyDebn's installer wrote goes
# (sources, key and pin) once none of its packages is installed, and a pin
# whose repo is gone goes too; a repo still in use, or one that isn't
# OhMyDebn's, is never touched. Runs against a scratch root
# (OHMYDEBN_TEST_ROOT); sudo really runs what it's given there, and
# dpkg-query reports the packages in MOCK_INSTALLED as installed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-apt-pins"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-apt-pins ==="

setup() {
  mock_init
  ROOT="$MOCK_DIR/root"
  APT="$ROOT/etc/apt"
  mkdir -p "$APT/sources.list.d" "$APT/preferences.d" "$APT/keyrings" "$ROOT/usr/share/keyrings"
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
"$@"
STUB
  # "rc" for a package removed without purging, which still has dpkg's
  # records but isn't installed.
  mock_bin dpkg-query <<'STUB'
#!/bin/bash
pkg="${!#}"
if [[ " ${MOCK_INSTALLED:-} " == *" $pkg "* ]]; then printf installed
elif [[ " ${MOCK_REMOVED:-} " == *" $pkg "* ]]; then printf config-files
else exit 1
fi
STUB
}
prune() { OUT=$(OHMYDEBN_TEST_ROOT="$ROOT" PATH="$(mock_path)" bash "$SCRIPT" --prune 2>&1); STATUS=$?; }
there() { [ -e "$ROOT$1" ] && echo yes || echo no; }
# repo <name> <pin> [key]: an OhMyDebn-written repo, as its installer leaves it.
repo() {
  : >"$APT/sources.list.d/$1.list"
  : >"$APT/preferences.d/$2"
  [ -n "${3:-}" ] && : >"$ROOT$3"
  return 0
}

# --- Claude Code removed with Remove > Package: its repo, key and pin go ---
setup
repo claude-code claude-code.pref /usr/share/keyrings/claude-code.asc
repo helium helium.pref /usr/share/keyrings/helium.gpg
MOCK_INSTALLED="helium-bin" prune
assert_eq "prune: succeeds" "0" "$STATUS"
assert_eq "app gone: its repo goes" "no" "$(there /etc/apt/sources.list.d/claude-code.list)"
assert_eq "app gone: its key goes" "no" "$(there /usr/share/keyrings/claude-code.asc)"
assert_eq "app gone: its pin goes" "no" "$(there /etc/apt/preferences.d/claude-code.pref)"
assert_contains "app gone: says so" "$OUT" "Removed the claude-code apt repository: nothing from it is installed any more."
assert_eq "app installed: its repo stays" "yes" "$(there /etc/apt/sources.list.d/helium.list)"
assert_eq "app installed: its key stays" "yes" "$(there /usr/share/keyrings/helium.gpg)"
assert_eq "app installed: its pin stays" "yes" "$(there /etc/apt/preferences.d/helium.pref)"
# Done: a second run has nothing to do.
: >"$MOCK_CALLS"
MOCK_INSTALLED="helium-bin" prune
assert_eq "again: nothing run" "" "$(cat "$MOCK_CALLS")"
assert_eq "again: nothing said" "" "$OUT"
mock_cleanup

# --- removed without purging: not installed, so the repo goes ---
setup
repo tailscale tailscale.pref /usr/share/keyrings/tailscale-archive-keyring.gpg
MOCK_REMOVED="tailscale" prune
assert_eq "removed, not purged: counts as gone" "no" "$(there /etc/apt/sources.list.d/tailscale.list)"
mock_cleanup

# --- Antigravity's key lives under /etc/apt/keyrings ---
setup
repo antigravity antigravity.pref /etc/apt/keyrings/antigravity-repo-key.gpg
prune
assert_eq "Antigravity gone: its key goes" "no" "$(there /etc/apt/keyrings/antigravity-repo-key.gpg)"
mock_cleanup

# --- Brave's one repo serves both variants: it stays while either is installed ---
setup
: >"$APT/sources.list.d/brave-browser-release.sources"
: >"$APT/preferences.d/brave-browser-release.pref"
MOCK_INSTALLED="brave-origin" prune
assert_eq "Brave Origin installed: the shared repo stays" "yes" "$(there /etc/apt/sources.list.d/brave-browser-release.sources)"
MOCK_INSTALLED="brave-browser" prune
assert_eq "Brave Browser installed: the shared repo stays" "yes" "$(there /etc/apt/sources.list.d/brave-browser-release.sources)"
prune
assert_eq "neither installed: the shared repo goes (.sources)" "no" "$(there /etc/apt/sources.list.d/brave-browser-release.sources)"
assert_eq "neither installed: its pin goes" "no" "$(there /etc/apt/preferences.d/brave-browser-release.pref)"
mock_cleanup

# --- a distro's own source for the same vendor is never touched (LCOS) ---
setup
echo "deb https://brave-browser-apt-release.s3.brave.com/ stable main" >"$APT/sources.list.d/brave.list"
prune
assert_eq "distro's Brave source: left alone" "yes" "$(there /etc/apt/sources.list.d/brave.list)"
mock_cleanup

# --- ...even with OhMyDebn's name: Zorin OS ships brave-browser-release.list
# (Brave's own instructions' name), with the keyring brave-keyring owns ---
setup
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" \
  >"$APT/sources.list.d/brave-browser-release.list"
: >"$ROOT/usr/share/keyrings/brave-browser-archive-keyring.gpg"
prune
assert_eq "Zorin OS's Brave .list, no Brave installed: left alone" "yes" "$(there /etc/apt/sources.list.d/brave-browser-release.list)"
assert_eq "Zorin OS's Brave .list: its keyring left alone" "yes" "$(there /usr/share/keyrings/brave-browser-archive-keyring.gpg)"
assert_eq "Zorin OS's Brave .list: nothing said" "" "$OUT"
mock_cleanup

# --- vendor-owned repos: the vendor's package removes the repo; the pin follows ---
setup
for pin in claude-desktop.pref google-chrome.pref chatgpt.pref code.pref; do
  : >"$APT/preferences.d/$pin"
done
: >"$APT/sources.list.d/chatgpt.sources"   # ChatGPT still installed: its repo is there
: >"$APT/preferences.d/my-own.pref"         # not OhMyDebn's
prune
assert_eq "vendor repo gone: Claude Desktop's pin goes" "no" "$(there /etc/apt/preferences.d/claude-desktop.pref)"
assert_eq "vendor repo gone: Chrome's pin goes" "no" "$(there /etc/apt/preferences.d/google-chrome.pref)"
assert_eq "vendor repo gone: VS Code's pin (repo vscode) goes" "no" "$(there /etc/apt/preferences.d/code.pref)"
assert_contains "vendor repo gone: says which pin and why" "$OUT" "claude-desktop.pref: its repository is gone."
assert_eq "vendor repo there (.sources): its pin stays" "yes" "$(there /etc/apt/preferences.d/chatgpt.pref)"
assert_eq "vendor repo there: never removed by us" "yes" "$(there /etc/apt/sources.list.d/chatgpt.sources)"
assert_eq "a pin that isn't OhMyDebn's is never touched" "yes" "$(there /etc/apt/preferences.d/my-own.pref)"
mock_cleanup

# --- PowerShell's repo stays while PowerShell or Microsoft's setup package is installed ---
setup
repo microsoft-prod powershell.pref /usr/share/keyrings/microsoft-prod.asc
MOCK_INSTALLED="powershell" prune
assert_eq "PowerShell installed: its repo stays" "yes" "$(there /etc/apt/sources.list.d/microsoft-prod.list)"
MOCK_INSTALLED="packages-microsoft-prod" prune
assert_eq "setup package installed (its own list): the repo stays" "yes" "$(there /etc/apt/sources.list.d/microsoft-prod.list)"
assert_eq "setup package installed: the pin stays" "yes" "$(there /etc/apt/preferences.d/powershell.pref)"
prune
assert_eq "neither installed: PowerShell's repo goes" "no" "$(there /etc/apt/sources.list.d/microsoft-prod.list)"
assert_eq "neither installed: its key goes" "no" "$(there /usr/share/keyrings/microsoft-prod.asc)"
assert_eq "neither installed: its pin goes" "no" "$(there /etc/apt/preferences.d/powershell.pref)"
mock_cleanup

# --- no preferences.d at all: fine ---
setup
rm -r "$APT/preferences.d"
prune
assert_eq "no preferences.d: succeeds" "0" "$STATUS"
mock_cleanup

# --- --list: one "repo:pin" line per repo ---
LIST=$(bash "$SCRIPT" --list)
assert_contains "list: Claude Desktop" "$LIST" "claude-desktop:claude-desktop.pref"
assert_contains "list: PowerShell's repo is Microsoft's" "$LIST" "microsoft-prod:powershell.pref"
assert_not_contains "list: just repo and pin" "$LIST" "keyrings"
bash "$SCRIPT" >/dev/null 2>&1
assert_eq "no argument: usage, exits 1" "1" "$?"

test_summary
