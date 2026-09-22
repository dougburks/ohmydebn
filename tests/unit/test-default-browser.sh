#!/bin/bash
#
# Unit tests for the default browser:
# install/packaging/browser.sh (installs Brave Origin on new installs only,
# falling back to Chromium), install/config/mimetypes.sh (makes whichever
# browser is present the default - Brave Origin first - on new installs
# only), bin/ohmydebn-browser-set-default (the one place the default is
# actually set: alternatives, xdg-settings, scheme handlers, PDF viewer -
# for mimetypes.sh, for the installers' prompt and for the menu's Browsers
# > Set Default), every bin/ohmydebn-<browser>-install's "make it your
# default?" question after an install picked from the menu (never under
# --skip-prompt, and defaulting to no), and bin/ohmydebn-firefox-esr, the
# launcher that replaced the menu's bare `apt install firefox-esr`.
# Existing installs are the important negative case throughout: they keep
# their browser unless the user says otherwise.
#
# The scripts' hardcoded /usr/share/ohmydebn paths are sed-patched to the
# mock bin dir; dpkg answers from MOCK_INSTALLED, snap from MOCK_SNAPS, and
# HOME is a scratch dir so the install-complete marker can be present or
# absent per scenario. mimetypes.sh runs against the REAL
# ohmydebn-browser-set-default (patched the same way), so its assertions
# are on the update-alternatives/xdg calls that actually result.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== install/packaging/browser.sh / install/config/mimetypes.sh / ohmydebn-chromium-install ==="

setup() {
  mock_init
  H="$MOCK_DIR/home"
  mkdir -p "$H"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  mock_bin snap <<'EOF2'
#!/bin/bash
[[ "$1" == "list" && " ${MOCK_SNAPS:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  for name in sudo xdg-settings xdg-mime ohmydebn-headline ohmydebn-brave-repo; do
    mock_bin "$name" <<EOF2
#!/bin/bash
echo "$name \$*" >>"\$MOCK_CALLS"
exit 0
EOF2
  done
  # ohmydebn-brave-origin-install succeeds unless MOCK_BRAVE_FAILS is set;
  # ohmydebn-chromium-install is mocked here (the real one is tested below).
  mock_bin ohmydebn-brave-origin-install <<'EOF2'
#!/bin/bash
echo "ohmydebn-brave-origin-install $*" >>"$MOCK_CALLS"
[[ -n "${MOCK_BRAVE_FAILS:-}" ]] && exit 1
exit 0
EOF2
  mock_bin ohmydebn-chromium-install <<'EOF2'
#!/bin/bash
echo "ohmydebn-chromium-install $*" >>"$MOCK_CALLS"
exit 0
EOF2
  for script in install/packaging/browser.sh install/config/mimetypes.sh; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/$script" >"$MOCK_DIR/$(basename "$script")"
  done
  # The real ohmydebn-browser-set-default, on the mock PATH under its own
  # name, so mimetypes.sh's call to it (patched above) runs it for real.
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-browser-set-default" >"$MOCK_BIN/ohmydebn-browser-set-default"
  chmod +x "$MOCK_BIN/ohmydebn-browser-set-default"
}
run() {
  HOME="$H" PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" MOCK_SNAPS="${MOCK_SNAPS:-}" \
    MOCK_BRAVE_FAILS="${MOCK_BRAVE_FAILS:-}" bash "$@" </dev/null >/dev/null 2>&1
}
# Same, with the given text as stdin (an installer's "Press Enter" plus a
# y/n answer) and stdout+stderr captured in OUT.
run_input() {
  local input="$1"
  shift
  OUT=$(HOME="$H" PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" MOCK_SNAPS="${MOCK_SNAPS:-}" \
    bash "$@" <<<"$input" 2>&1)
}

# --- browser.sh: new install -> Brave Origin installed, no fallback ---
setup
run "$MOCK_DIR/browser.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "new install: Brave Origin installed without prompting" "$CALLS" "ohmydebn-brave-origin-install --skip-prompt"
assert_not_contains "new install: no Chromium fallback when Brave Origin succeeds" "$CALLS" "ohmydebn-chromium-install"
mock_cleanup

# --- browser.sh: existing install -> untouched (keeps Chromium) ---
setup
mkdir -p "$H/.local/state"
touch "$H/.local/state/ohmydebn"
run "$MOCK_DIR/browser.sh"
assert_eq "existing install: nothing installed" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- browser.sh: Brave Origin install fails -> its repo (ours) removed, Chromium installed ---
setup
mock_bin ohmydebn-brave-repo <<'EOF2'
#!/bin/bash
echo "ohmydebn-brave-repo $*" >>"$MOCK_CALLS"
exit 0
EOF2
MOCK_BRAVE_FAILS=1 run "$MOCK_DIR/browser.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "brave fails: repo we added is removed again" "$CALLS" "ohmydebn-brave-repo remove"
assert_contains "brave fails: Chromium installed as the fallback" "$CALLS" "ohmydebn-chromium-install --skip-prompt"
mock_cleanup

# --- browser.sh: Brave Origin install fails on a distro whose repo it isn't ours -> repo left alone ---
setup
mock_bin ohmydebn-brave-repo <<'EOF2'
#!/bin/bash
echo "ohmydebn-brave-repo $*" >>"$MOCK_CALLS"
[[ "$1" == is-ours ]] && exit 1
exit 0
EOF2
MOCK_BRAVE_FAILS=1 run "$MOCK_DIR/browser.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "brave fails, distro repo: not removed" "$CALLS" "ohmydebn-brave-repo remove"
assert_contains "brave fails, distro repo: Chromium still the fallback" "$CALLS" "ohmydebn-chromium-install --skip-prompt"
mock_cleanup

# --- mimetypes.sh: new install with Brave Origin -> it becomes the default browser and PDF viewer ---
setup
MOCK_INSTALLED="brave-origin chromium" run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "new install: Brave Origin wins over an also-present Chromium (xdg default)" "$CALLS" "xdg-settings set default-web-browser brave-origin.desktop"
assert_contains "new install: http handler" "$CALLS" "xdg-mime default brave-origin.desktop x-scheme-handler/http"
assert_contains "new install: https handler" "$CALLS" "xdg-mime default brave-origin.desktop x-scheme-handler/https"
assert_contains "new install: x-www-browser selects the path Brave's package registered" "$CALLS" "sudo update-alternatives --set x-www-browser /usr/bin/brave-origin-stable"
assert_contains "new install: gnome-www-browser too" "$CALLS" "sudo update-alternatives --set gnome-www-browser /usr/bin/brave-origin-stable"
assert_contains "new install: PDF viewer" "$CALLS" "xdg-mime default brave-origin.desktop application/pdf"
assert_contains "new install: headline names the browser" "$CALLS" "ohmydebn-headline Configuring Brave Origin as default web browser"
assert_not_contains "new install: chromium not configured" "$CALLS" "chromium.desktop"
assert_eq "new install: PDF marker written" "yes" "$([ -f "$H/.local/state/ohmydebn-config/pdf-20251107" ] && echo yes || echo no)"
mock_cleanup

# --- mimetypes.sh: new install where only Chromium is present (fallback) -> Chromium as before ---
setup
MOCK_INSTALLED="chromium" run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "chromium only: xdg default" "$CALLS" "xdg-settings set default-web-browser chromium.desktop"
assert_contains "chromium only: alternative" "$CALLS" "sudo update-alternatives --set x-www-browser /usr/bin/chromium"
assert_contains "chromium only: PDF viewer" "$CALLS" "xdg-mime default chromium.desktop application/pdf"
mock_cleanup

# --- mimetypes.sh: new install, Ubuntu snap chromium only -> snap desktop id and binary ---
setup
MOCK_SNAPS="chromium" run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "snap chromium: xdg default" "$CALLS" "xdg-settings set default-web-browser chromium_chromium.desktop"
assert_contains "snap chromium: alternative" "$CALLS" "sudo update-alternatives --set x-www-browser /snap/bin/chromium"
mock_cleanup

# --- mimetypes.sh: no browser at all -> only the image viewer step ---
setup
run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "no browser: no default-browser step" "$CALLS" "default-web-browser"
assert_not_contains "no browser: no PDF step" "$CALLS" "application/pdf"
assert_contains "no browser: ristretto still configured" "$CALLS" "org.xfce.ristretto.desktop"
mock_cleanup

# --- mimetypes.sh: existing install (marker + PDF marker) with Brave Origin newly present -> untouched ---
setup
mkdir -p "$H/.local/state/ohmydebn-config"
touch "$H/.local/state/ohmydebn" "$H/.local/state/ohmydebn-config/pdf-20251107"
MOCK_INSTALLED="brave-origin chromium" run "$MOCK_DIR/mimetypes.sh"
assert_eq "existing install: default browser and PDF viewer left alone" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- mimetypes.sh: existing install without the PDF marker -> PDF only, browser default untouched ---
setup
mkdir -p "$H/.local/state"
touch "$H/.local/state/ohmydebn"
MOCK_INSTALLED="chromium" run "$MOCK_DIR/mimetypes.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "existing install, no PDF marker: default browser untouched" "$CALLS" "default-web-browser"
assert_contains "existing install, no PDF marker: PDF step still runs" "$CALLS" "xdg-mime default chromium.desktop application/pdf"
mock_cleanup

# --- ohmydebn-chromium-install: real script; apt logged, os-release and the seed source patched ---
setup_chromium() {
  setup
  ROOT="$MOCK_DIR/root"
  mkdir -p "$ROOT/usr/share/ohmydebn/config/chromium/External Extensions" "$ROOT/etc"
  echo '{}' >"$ROOT/usr/share/ohmydebn/config/chromium/External Extensions/x.json"
  echo "ID=$1" >"$ROOT/etc/os-release"
  sed "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g; s#/etc/os-release#$ROOT/etc/os-release#g" \
    "$REPO_ROOT/install/config/chromium.sh" >"$ROOT/chromium.sh"
  mkdir -p "$ROOT/usr/share/ohmydebn/install/config" "$ROOT/usr/share/ohmydebn/bin"
  mv "$ROOT/chromium.sh" "$ROOT/usr/share/ohmydebn/install/config/chromium.sh"
  # chromium.sh's headline call is patched to the scratch root too - it has
  # to exist there, or `set -e` in the installer ends the seed step early.
  ln -s "$MOCK_BIN/ohmydebn-headline" "$ROOT/usr/share/ohmydebn/bin/ohmydebn-headline"
  mock_set_default_logger
  sed "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g; s#/etc/os-release#$ROOT/etc/os-release#g" \
    "$REPO_ROOT/bin/ohmydebn-chromium-install" >"$MOCK_DIR/chromium-install.sh"
}
# For the installers, ohmydebn-browser-set-default is only logged (its own
# behaviour is tested separately below) - replaces the real one setup()
# put on the mock PATH, and links it into the scratch root the installers
# are patched to.
mock_set_default_logger() {
  mock_bin ohmydebn-browser-set-default <<'EOF2'
#!/bin/bash
echo "ohmydebn-browser-set-default $*" >>"$MOCK_CALLS"
exit 0
EOF2
  mkdir -p "$ROOT/usr/share/ohmydebn/bin"
  ln -sf "$MOCK_BIN/ohmydebn-browser-set-default" "$ROOT/usr/share/ohmydebn/bin/ohmydebn-browser-set-default"
}

# Debian, not installed: prompt skipped, chromium installed without recommends
setup_chromium debian
run "$MOCK_DIR/chromium-install.sh" --skip-prompt
assert_contains "debian: installs chromium" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y --no-install-recommends install chromium"
assert_not_contains "debian, --skip-prompt: no default-browser question (a new install's mimetypes.sh has it)" "$(cat "$MOCK_CALLS")" "ohmydebn-browser-set-default"
mock_cleanup

# Debian, not installed, from the menu (no --skip-prompt): Enter at the
# prompt installs it, then the default-browser question follows the install
setup_chromium debian
run_input "" "$MOCK_DIR/chromium-install.sh"
assert_contains "menu install: installs chromium" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y --no-install-recommends install chromium"
assert_eq "menu install: asks about the default browser, after the install" "yes" \
  "$(grep -A99 'apt -y --no-install-recommends install chromium' "$MOCK_CALLS" | grep -q 'ohmydebn-browser-set-default --ask chromium' && echo yes || echo no)"
mock_cleanup

# Ubuntu, not installed: the transitional chromium-browser package instead
setup_chromium ubuntu
run "$MOCK_DIR/chromium-install.sh" --skip-prompt
assert_contains "ubuntu: installs chromium-browser" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y --no-install-recommends install chromium-browser"
mock_cleanup

# Debian, already installed, no profile yet: no apt, uBlock seed applied
setup_chromium debian
MOCK_INSTALLED="chromium" run "$MOCK_DIR/chromium-install.sh" --skip-prompt
assert_not_contains "installed: no apt call" "$(cat "$MOCK_CALLS")" "apt"
assert_eq "installed: uBlock Origin Lite seeded into a fresh profile" "yes" "$([ -f "$H/.config/chromium/External Extensions/x.json" ] && echo yes || echo no)"
mock_cleanup

# Debian, installed with an existing profile: never overwritten
setup_chromium debian
mkdir -p "$H/.config/chromium"
MOCK_INSTALLED="chromium" run "$MOCK_DIR/chromium-install.sh" --skip-prompt
assert_eq "existing profile: left alone" "no" "$([ -e "$H/.config/chromium/External Extensions" ] && echo yes || echo no)"
mock_cleanup

# Without --skip-prompt and stdin closed: the prompt's read fails, nothing installed
setup_chromium debian
run "$MOCK_DIR/chromium-install.sh"
EXIT_CODE=$?
assert_eq "cancelled at the prompt: exits non-zero" "1" "$EXIT_CODE"
assert_not_contains "cancelled at the prompt: nothing installed" "$(cat "$MOCK_CALLS")" "apt"
mock_cleanup

# --- every other browser installer: the same question, in the same place ---
#
# Each installer is patched to a scratch root and run twice from the menu's
# point of view (Enter at its own prompt) - once fresh, where it must ask
# right after installing, and for the ones that take --skip-prompt, once
# that way, where it must not. Everything that would touch the system
# (sudo, curl, gpg) is a logging stub.
setup_installer() {
  setup
  ROOT="$MOCK_DIR/root"
  mkdir -p "$ROOT/usr/share/ohmydebn/bin" "$ROOT/usr/share/ohmydebn/config/net.imput.helium/Default" "$H/.config"
  echo '{}' >"$ROOT/usr/share/ohmydebn/config/net.imput.helium/Default/Preferences"
  mock_set_default_logger
  for name in ohmydebn-headline ohmydebn-brave-repo; do
    ln -sf "$MOCK_BIN/$name" "$ROOT/usr/share/ohmydebn/bin/$name"
  done
  for name in curl gpg; do
    mock_bin "$name" <<'EOF2'
#!/bin/bash
exit 0
EOF2
  done
  mock_bin uname <<'EOF2'
#!/bin/bash
echo x86_64
EOF2
  sed "s#/usr/share/ohmydebn#$ROOT/usr/share/ohmydebn#g" "$REPO_ROOT/bin/$1" >"$MOCK_DIR/installer.sh"
}
# (installer/label rather than script/name: setup() loops over globals of
# those names, so a loop here that reused them would be clobbered per case.)

for spec in "ohmydebn-brave-origin-install brave-origin skip" \
  "ohmydebn-brave-browser-install brave-browser skip" \
  "ohmydebn-google-chrome-stable-install google-chrome-stable -" \
  "ohmydebn-helium-bin-install helium-bin -" \
  "ohmydebn-firefox-esr-install firefox-esr -"; do
  read -r installer pkg skip <<<"$spec"

  setup_installer "$installer"
  run_input "" "$MOCK_DIR/installer.sh"
  CALLS=$(cat "$MOCK_CALLS")
  assert_eq "$installer: installs the package" "yes" "$(grep -qE "apt -y install $pkg|dpkg -i" "$MOCK_CALLS" && echo yes || echo no)"
  assert_eq "$installer: asks about the default browser, after the install" "yes" \
    "$(grep -A99 -E "apt -y install|dpkg -i" "$MOCK_CALLS" | grep -q "ohmydebn-browser-set-default --ask $pkg" && echo yes || echo no)"
  mock_cleanup

  setup_installer "$installer"
  MOCK_INSTALLED="$pkg" run_input "" "$MOCK_DIR/installer.sh"
  assert_not_contains "$installer: already installed, nothing to ask" "$(cat "$MOCK_CALLS")" "ohmydebn-browser-set-default"
  mock_cleanup

  if [[ "$skip" == skip ]]; then
    setup_installer "$installer"
    run "$MOCK_DIR/installer.sh" --skip-prompt
    CALLS=$(cat "$MOCK_CALLS")
    assert_contains "$installer --skip-prompt: still installs" "$CALLS" "apt -y install $pkg"
    assert_not_contains "$installer --skip-prompt: no default-browser question" "$CALLS" "ohmydebn-browser-set-default"
    mock_cleanup
  fi
done

# --- ohmydebn-browser-set-default itself: the real script against logging stubs ---
#
# setup() already puts it on the mock PATH; sudo/xdg-settings/xdg-mime/
# ohmydebn-headline only log. The alternatives entry must name the exact
# path each package's postinst registered, the desktop id the .desktop
# each package actually ships - both checked against the real packages.
# (SET_DEFAULT is set after each setup(): the mock dir is fresh per case.)
set_default() { SET_DEFAULT="$MOCK_BIN/ohmydebn-browser-set-default"; }

for spec in "brave-origin /usr/bin/brave-origin-stable brave-origin.desktop Brave Origin" \
  "brave-browser /usr/bin/brave-browser-stable brave-browser.desktop Brave Browser" \
  "chromium /usr/bin/chromium chromium.desktop Chromium" \
  "google-chrome-stable /usr/bin/google-chrome-stable google-chrome.desktop Google Chrome" \
  "helium-bin /usr/bin/helium helium.desktop Helium" \
  "firefox-esr /usr/bin/firefox-esr firefox-esr.desktop Firefox"; do
  read -r pkg bin desktop label <<<"$spec"
  setup
  set_default
  MOCK_INSTALLED="$pkg" run "$SET_DEFAULT" "$pkg"
  EXIT_CODE=$?
  CALLS=$(cat "$MOCK_CALLS")
  assert_eq "$pkg: succeeds" "0" "$EXIT_CODE"
  assert_contains "$pkg: x-www-browser alternative is the package's registered path" "$CALLS" "sudo update-alternatives --set x-www-browser $bin"
  assert_contains "$pkg: gnome-www-browser too" "$CALLS" "sudo update-alternatives --set gnome-www-browser $bin"
  assert_contains "$pkg: registered at priority 200 first (Helium's package registers none)" "$CALLS" "sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser $bin 200"
  assert_contains "$pkg: xdg default" "$CALLS" "xdg-settings set default-web-browser $desktop"
  assert_contains "$pkg: http handler" "$CALLS" "xdg-mime default $desktop x-scheme-handler/http"
  assert_contains "$pkg: https handler" "$CALLS" "xdg-mime default $desktop x-scheme-handler/https"
  assert_contains "$pkg: PDF viewer follows the browser" "$CALLS" "xdg-mime default $desktop application/pdf"
  assert_contains "$pkg: headline names the browser" "$CALLS" "ohmydebn-headline Configuring $label as default web browser"
  mock_cleanup
done

# Ubuntu: chromium is a snap only -> the snap's binary and desktop id
setup
set_default
MOCK_SNAPS="chromium" run "$SET_DEFAULT" chromium
CALLS=$(cat "$MOCK_CALLS")
assert_contains "snap chromium: alternative" "$CALLS" "sudo update-alternatives --set x-www-browser /snap/bin/chromium"
assert_contains "snap chromium: xdg default" "$CALLS" "xdg-settings set default-web-browser chromium_chromium.desktop"
mock_cleanup

# Not installed: refused, with a pointer to where to install it, nothing touched
setup
set_default
run_input "" "$SET_DEFAULT" google-chrome-stable
EXIT_CODE=$?
assert_eq "not installed: exits non-zero" "1" "$EXIT_CODE"
assert_contains "not installed: says so and where to install it" "$OUT" "Google Chrome is not installed. Install it first: OhMyDebn Menu > Apps > Browsers."
assert_eq "not installed: nothing configured" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# Unknown package: usage, nothing touched
setup
set_default
run "$SET_DEFAULT" lynx
EXIT_CODE=$?
assert_eq "unknown package: exits non-zero" "1" "$EXIT_CODE"
assert_eq "unknown package: nothing configured" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --ask: "y" applies it
setup
set_default
MOCK_INSTALLED="helium-bin" run_input "y" "$SET_DEFAULT" --ask helium-bin
CALLS=$(cat "$MOCK_CALLS")
assert_contains "--ask y: asked" "$OUT" "Make Helium your default web browser? [y/N]"
assert_contains "--ask y: applied" "$CALLS" "xdg-settings set default-web-browser helium.desktop"
mock_cleanup

# --ask: a bare Enter is "no" - the installer's own "Press Enter to
# continue" comes right before this, so a reflexive second Enter must not
# take over the default; "n" is no too. Either is a success, not an error,
# and says where to change it later.
for answer in "" "n" "N"; do
  setup
  set_default
  MOCK_INSTALLED="helium-bin" run_input "$answer" "$SET_DEFAULT" --ask helium-bin
  EXIT_CODE=$?
  assert_eq "--ask '$answer': exits zero" "0" "$EXIT_CODE"
  assert_eq "--ask '$answer': nothing configured" "" "$(cat "$MOCK_CALLS")"
  assert_contains "--ask '$answer': says where to change it later" "$OUT" "OhMyDebn Menu > Apps > Browsers > Set Default"
  mock_cleanup
done

# --ask on a browser that isn't installed: refused before the question
setup
set_default
run_input "y" "$SET_DEFAULT" --ask helium-bin
EXIT_CODE=$?
assert_eq "--ask, not installed: exits non-zero" "1" "$EXIT_CODE"
assert_not_contains "--ask, not installed: never asks" "$OUT" "[y/N]"
mock_cleanup

# --pdf-only: the PDF viewer and nothing else
setup
set_default
MOCK_INSTALLED="chromium" run "$SET_DEFAULT" --pdf-only chromium
CALLS=$(cat "$MOCK_CALLS")
assert_contains "--pdf-only: PDF viewer set" "$CALLS" "xdg-mime default chromium.desktop application/pdf"
assert_not_contains "--pdf-only: default browser untouched" "$CALLS" "default-web-browser"
assert_not_contains "--pdf-only: alternatives untouched" "$CALLS" "update-alternatives"
mock_cleanup

# A failing step (sudo denied) doesn't stop the rest, and is reported
setup
set_default
mock_bin sudo <<'EOF2'
#!/bin/bash
echo "sudo $*" >>"$MOCK_CALLS"
exit 1
EOF2
MOCK_INSTALLED="firefox-esr" run_input "" "$SET_DEFAULT" firefox-esr
EXIT_CODE=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "sudo denied: exits non-zero" "1" "$EXIT_CODE"
assert_contains "sudo denied: xdg half still applied" "$CALLS" "xdg-settings set default-web-browser firefox-esr.desktop"
assert_contains "sudo denied: warns" "$OUT" "not every default-browser setting could be applied"
mock_cleanup

# --- ohmydebn-firefox-esr: the launcher behind the menu's Firefox entry ---
#
# Not installed -> the installer in a floating terminal (with a title);
# installed -> Firefox itself. /usr/bin/firefox-esr is patched to a stub.
setup_firefox() {
  setup
  mock_bin ohmydebn-launch-floating-terminal-with-presentation <<'EOF2'
#!/bin/bash
echo "ohmydebn-launch-floating-terminal-with-presentation $*" >>"$MOCK_CALLS"
EOF2
  mock_bin firefox-esr <<'EOF2'
#!/bin/bash
echo "firefox-esr $*" >>"$MOCK_CALLS"
EOF2
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/bin/firefox-esr#$MOCK_BIN/firefox-esr#g" \
    "$REPO_ROOT/bin/ohmydebn-firefox-esr" >"$MOCK_DIR/firefox.sh"
}
setup_firefox
run "$MOCK_DIR/firefox.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "firefox launcher, not installed: installer in a titled floating terminal" "$CALLS" "ohmydebn-launch-floating-terminal-with-presentation Firefox $MOCK_BIN/ohmydebn-firefox-esr-install"
assert_not_contains "firefox launcher, not installed: not launched" "$CALLS" "firefox-esr "
mock_cleanup

setup_firefox
MOCK_INSTALLED="firefox-esr" run "$MOCK_DIR/firefox.sh"
CALLS=$(cat "$MOCK_CALLS")
assert_contains "firefox launcher, installed: launched" "$CALLS" "firefox-esr "
assert_not_contains "firefox launcher, installed: no installer" "$CALLS" "floating-terminal"
mock_cleanup

test_summary
