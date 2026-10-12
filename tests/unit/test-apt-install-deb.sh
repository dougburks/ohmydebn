#!/bin/bash
#
# Unit tests for bin/ohmydebn-apt-install-deb, which installs a vendor's
# .deb from a URL through apt, and for the installers that use it
# (ChatGPT and VS Code here; Google Chrome is covered in
# test-default-browser.sh). They used to `curl && dpkg -i && rm`: dpkg -i
# doesn't install dependencies, a failed download skipped the install but
# the installer still exited 0 and carried on (VS Code wrote its pin for a
# package that wasn't there), and the temporary file stayed behind.
#
# sudo and curl are loggers (curl writes or fails as told), and TMPDIR is
# a scratch directory, so nothing here downloads or installs anything.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$REPO_ROOT/bin/ohmydebn-apt-install-deb"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-apt-install-deb and the installers that use it ==="

# setup <curl behavior: ok|fail> [content curl writes]
setup() {
  mock_init
  mkdir -p "$MOCK_DIR/tmp" "$MOCK_DIR/root/usr/share/ohmydebn/bin"
  echo "${2:-the package}" >"$MOCK_DIR/payload"
  mock_bin sudo <<'STUB'
#!/bin/bash
mock_log "sudo $*"
STUB
  if [ "$1" = ok ]; then
    mock_bin curl <<'STUB'
#!/bin/bash
mock_log "curl $*"
while [ $# -gt 0 ]; do [ "$1" = "-o" ] && cp "$MOCK_DIR/payload" "$2"; shift; done
exit 0
STUB
  else
    mock_bin curl <<'STUB'
#!/bin/bash
mock_log "curl $*"
exit 22
STUB
  fi
}

run_helper() {
  OUTPUT=$(TMPDIR="$MOCK_DIR/tmp" PATH="$(mock_path)" bash "$HELPER" "$@" </dev/null 2>&1)
  STATUS=$?
}

no_leftovers() {
  [ -z "$(ls -A "$MOCK_DIR/tmp")" ] && echo yes || echo no
}

# --- download works: apt update, then apt installs the downloaded file ---
setup ok
run_helper "Thing" "https://example.com/thing.deb"
assert_eq "download works: exits 0" "0" "$STATUS"
assert_contains "download works: apt update first" "$(head -2 "$MOCK_CALLS" | tail -1)" "sudo /usr/bin/apt update"
assert_contains "download works: apt installs the downloaded .deb (with its dependencies)" \
  "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y install $MOCK_DIR/tmp/"
assert_not_contains "download works: never dpkg -i" "$(cat "$MOCK_CALLS")" "dpkg -i"
assert_eq "download works: the download is removed afterwards" "yes" "$(no_leftovers)"
mock_cleanup

# --- download fails: says so, installs nothing, leaves nothing ---
setup fail
run_helper "Thing" "https://example.com/thing.deb"
assert_eq "download fails: exits non-zero" "1" "$STATUS"
assert_contains "download fails: says why" "$OUTPUT" "Couldn't download Thing"
assert_not_contains "download fails: nothing installed" "$(cat "$MOCK_CALLS")" "sudo"
assert_eq "download fails: nothing left behind" "yes" "$(no_leftovers)"
mock_cleanup

# --- a published checksum is checked before anything is installed ---
setup ok "the package"
GOOD=$(echo "the package" | sha256sum | cut -d' ' -f1)
run_helper "Thing" "https://example.com/thing.deb" "$GOOD"
assert_eq "checksum matches: installed" "0" "$STATUS"
assert_contains "checksum matches: says so" "$OUTPUT" "Checksum verified."
assert_contains "checksum matches: apt installs it" "$(cat "$MOCK_CALLS")" "apt -y install"
mock_cleanup

setup ok "something else"
run_helper "Thing" "https://example.com/thing.deb" "$GOOD"
assert_eq "checksum mismatch: exits non-zero" "1" "$STATUS"
assert_contains "checksum mismatch: says why" "$OUTPUT" "doesn't match its published checksum"
assert_not_contains "checksum mismatch: nothing installed" "$(cat "$MOCK_CALLS")" "sudo"
assert_eq "checksum mismatch: nothing left behind" "yes" "$(no_leftovers)"
mock_cleanup

# --- the installers: a failed download stops them before their next step ---
# installer setup: the real helper copied into a scratch
# /usr/share/ohmydebn/bin, dpkg saying nothing is installed, and the
# default-AI question logged.
setup_installer() {
  setup "$1"
  cp "$HELPER" "$MOCK_DIR/root/usr/share/ohmydebn/bin/"
  mock_bin dpkg <<'STUB'
#!/bin/bash
exit 1
STUB
  mock_bin uname <<'STUB'
#!/bin/bash
echo x86_64
STUB
  mock_bin ohmydebn-ai-set-default <<'STUB'
#!/bin/bash
mock_log "ohmydebn-ai-set-default $*"
STUB
  ln -s "$MOCK_BIN/ohmydebn-ai-set-default" "$MOCK_DIR/root/usr/share/ohmydebn/bin/ohmydebn-ai-set-default"
  sed "s#/usr/share/ohmydebn#$MOCK_DIR/root/usr/share/ohmydebn#g" "$REPO_ROOT/bin/$2" >"$MOCK_DIR/installer"
}

run_installer() {
  OUTPUT=$(TMPDIR="$MOCK_DIR/tmp" PATH="$(mock_path)" bash "$MOCK_DIR/installer" <<<"" 2>&1)
  STATUS=$?
}

setup_installer fail ohmydebn-chatgpt-install
run_installer
assert_eq "ChatGPT, download fails: the installer fails (it used to exit 0)" "1" "$STATUS"
assert_not_contains "ChatGPT, download fails: no default-AI question for an app that isn't there" \
  "$(cat "$MOCK_CALLS")" "ohmydebn-ai-set-default"
mock_cleanup

setup_installer ok ohmydebn-chatgpt-install
run_installer
assert_contains "ChatGPT: the amd64 .deb is downloaded" "$(cat "$MOCK_CALLS")" "chatgpt_amd64.deb"
assert_contains "ChatGPT: installed through apt" "$(cat "$MOCK_CALLS")" "apt -y install"
assert_contains "ChatGPT: then asks about the default AI" "$(cat "$MOCK_CALLS")" "ohmydebn-ai-set-default --ask chatgpt"
mock_cleanup

# VS Code: the update API names the .deb and its checksum; curl answers it
# with that JSON, and the download with the package itself.
setup_installer ok ohmydebn-code-install
mock_bin curl <<'STUB'
#!/bin/bash
mock_log "curl $*"
case "$*" in
*update.code.visualstudio.com*)
  printf '{"url":"https://dl.example.com/code_1.0_amd64.deb","sha256hash":"%s"}\n' "$(echo "the package" | sha256sum | cut -d' ' -f1)"
  ;;
*) while [ $# -gt 0 ]; do [ "$1" = "-o" ] && cp "$MOCK_DIR/payload" "$2"; shift; done ;;
esac
STUB
run_installer
assert_eq "VS Code: installs" "0" "$STATUS"
assert_contains "VS Code: asks the update API for the x64 .deb" "$(cat "$MOCK_CALLS")" "api/update/linux-deb-x64/stable/latest"
assert_contains "VS Code: downloads the .deb the API names" "$(cat "$MOCK_CALLS")" "https://dl.example.com/code_1.0_amd64.deb"
assert_contains "VS Code: the published checksum is verified" "$OUTPUT" "Checksum verified."
assert_contains "VS Code: then pins Microsoft's repo to code" "$(cat "$MOCK_CALLS")" "tee /etc/apt/preferences.d/code.pref"
mock_cleanup

setup_installer fail ohmydebn-code-install
run_installer
assert_eq "VS Code, update API unreachable: the installer fails" "1" "$STATUS"
assert_contains "VS Code, update API unreachable: says why" "$OUTPUT" "Couldn't find the current Visual Studio Code download"
assert_not_contains "VS Code, update API unreachable: no pin written for a package that isn't there (it used to be)" \
  "$(cat "$MOCK_CALLS")" "code.pref"
mock_cleanup

test_summary
