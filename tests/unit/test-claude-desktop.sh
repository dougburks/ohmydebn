#!/bin/bash
#
# Unit tests for Claude Desktop: bin/ohmydebn-claude-desktop-install (adds
# Anthropic's repository - its key checked against the published
# fingerprint first, its sources file written with the package's own
# marker so the package manages it - pins it to claude-desktop, installs,
# and asks about the default AI), bin/ohmydebn-claude-desktop-remove, and
# bin/ohmydebn-pgp-fingerprint, the fingerprint check itself.
#
# dpkg, curl, sudo and apt are stand-ins: sudo only logs (and keeps what
# would have been written with tee), so nothing touches the real system.
# The key fixture is Anthropic's real public key, as their package's
# postinst embeds it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== Claude Desktop install/remove and ohmydebn-pgp-fingerprint ==="

FINGERPRINT_SCRIPT="$REPO_ROOT/bin/ohmydebn-pgp-fingerprint"

write_key() {
  cat >"$1" <<'KEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGnK73ABEACnbytJXkjweYrwIr0aLEFRlH+C0nF44KxFc7gQmJ6PjSPMGZAD
dxZcaixU7zZl8WxEpVO0wLmIH8cf2zGOdyuZg1Yaugk1vHb2b8WBhAGCQJdPgB8W
XquedepEYtk56uP/gCoTjJDUZluEGBHnlnuujSJ4orxEdhSykEoAUfJZGEILPpMd
bphFt/Sn+Eb/TxM5jpKPdwnv8AShNF/1mZU1fWTQq9tRKJUakZj04gdaDFElQXak
CtTij+GT6yoYCARSHwGO+PC/Pr6q4tc+D7LRjxSBvUWDoFSmlqb/PJ1hj9D/7I2O
e4XXniAPWMR56KvxHlzOzrNQdJujbJdSkCwh1ZijkSd3y8ayW5WYUTGdRab99NUw
agzlabe/VVF6kzJ0Scn5q3PihB2Y9Bwo0CKnkYk7a7KT77EWv0Kkq+VHmOtqX3a2
hhX+b6a6ve9rzJ1qZYGj+obv/C3Sx1LzUjAfqVy7RJDf2uAoP5t2g8u/TkSpUxhM
VEjZBkSxYZhMyzQM6t8IgkUfnSrIPTHixbDWARZ4beMOBjxyPZK1nP7OOrNR3TkK
JtwLMQAabURCDnL0PjS0iwBTU4jtumBD1XSULyWuoTvMljrpQr1nV1oDyOt0OLqa
KA2McWtd9PdXhC8y2EIg7TmrTlJLfHYbdmkiCYj4J49Q8HWkN/6WE+RTUwARAQAB
tD5BbnRocm9waWMgQ2xhdWRlIENvZGUgUmVsZWFzZSBTaWduaW5nIDxzZWN1cml0
eUBhbnRocm9waWMuY29tPokCUQQTAQoAOxYhBDHd3iTd+rZ59C170rqpKf8afsrO
BQJpyu9wAhsPBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4HAheAAAoJELqpKf8afsrO
l5IP/2I8X1dFy5xYczWB/coIxGjuzS/V6ByZGZZEJsbr04pmuHiFUykJqPGWGQ6q
U0YF5iEwvEkaagS5m7DzhSEf3FM3Cgafax/6d70tar9Vr1D+w6uPfxetu7u/WYJp
aolIsdh5fTrBh9zSM1Njl8FM8wG8CwZQjS33Oa7d8cwRkgdUWbt6LXgz+cTQNuBn
BgW6Ks7oZFI25dfu0ojDR+aDFJg4+4wZoyDLPvJz1SIrJ5WFGs67zsx9SfS3yZnf
XKmBe+f0dUy+GJ2nFZrXFf99+c0dPEHYO8DCeAHZizjkFrdYtUHdDU0YDYEGkLJa
bE+pgcpkHf5EvsZzHsyDbl95W/eh7pcXMbwkN+W4CBYUE9X4uHhqzWaC5yAVRWUA
1BJ9V4LjZfHPLEJt0I3TxzXiEg9/BVeaTYq9RjaxIFo9Nfk158HqJY6SA5jslBlx
Gv/No8u+xVcze2UJyGVfEIUfm92+0UAIkny3+5cuVV0ICzJxXlXj0CnLM9Lt50wE
p3suVwuBEviCbZ08eAH1Ht8gbBdSsiOkIU8CX3v/scwHHx5q0+NBL6xLrQObg13a
tRXBlKObfElkPN3lTUbUnJOW4U8uSjH8VRP+AujKWMDFe7x0zCs+iYY1mTOvbrTS
9n3CmZUmbynZ+E/QWNENpW/pDNZdWFy43PASmML5FHu4m9Sn
=oqMI
-----END PGP PUBLIC KEY BLOCK-----
KEY
}
FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

# --- ohmydebn-pgp-fingerprint ---
mock_init
write_key "$MOCK_DIR/key.asc"
assert_eq "fingerprint: Anthropic's armored key" "$FPR" "$(python3 -I "$FINGERPRINT_SCRIPT" "$MOCK_DIR/key.asc")"
# The same key without its armor: the base64 body between the blank line
# and the checksum line.
sed -n '/^$/,/^=/p' "$MOCK_DIR/key.asc" | grep -v -e '^$' -e '^=' | base64 -d >"$MOCK_DIR/key.gpg"
assert_eq "fingerprint: the same key, binary" "$FPR" "$(python3 -I "$FINGERPRINT_SCRIPT" "$MOCK_DIR/key.gpg")"
# One changed character in the key material: a different key.
sed '3s/^mQINBGnK73AB/mQINBGnK73AC/' "$MOCK_DIR/key.asc" >"$MOCK_DIR/tampered.asc"
OUT=$(python3 -I "$FINGERPRINT_SCRIPT" "$MOCK_DIR/tampered.asc")
assert_eq "fingerprint: a tampered key has another fingerprint" "yes" "$([ -n "$OUT" ] && [ "$OUT" != "$FPR" ] && echo yes || echo no)"
echo "<html>Not Found</html>" >"$MOCK_DIR/page.html"
python3 -I "$FINGERPRINT_SCRIPT" "$MOCK_DIR/page.html" >"$MOCK_DIR/out" 2>&1
assert_eq "fingerprint: not a key: exits 1" "1" "$?"
assert_eq "fingerprint: not a key: prints nothing" "" "$(cat "$MOCK_DIR/out")"
python3 -I "$FINGERPRINT_SCRIPT" "$MOCK_DIR/missing" >/dev/null 2>&1
assert_eq "fingerprint: no such file: exits 1" "1" "$?"
mock_cleanup

# --- the installer ---
# setup: stand-ins, with the real fingerprint helper. MOCK_KEY is the key
# curl "downloads"; MOCK_ARCH what dpkg reports; MOCK_INSTALLED makes
# dpkg -s claude-desktop succeed.
setup() {
  mock_init
  write_key "$MOCK_DIR/good.asc"
  sed '3s/^mQINBGnK73AB/mQINBGnK73AC/' "$MOCK_DIR/good.asc" >"$MOCK_DIR/bad.asc"
  mock_bin dpkg <<'EOF'
#!/bin/bash
[ "$1" = --print-architecture ] && { echo "${MOCK_ARCH:-amd64}"; exit 0; }
[ "$1" = -s ] && [ -n "${MOCK_INSTALLED:-}" ] && exit 0
exit 1
EOF
  mock_bin curl <<'EOF'
#!/bin/bash
mock_log "curl $*"
while [ $# -gt 0 ]; do
  [ "$1" = -o ] && cp "$MOCK_DIR/${MOCK_KEY:-good}.asc" "$2"
  shift
done
EOF
  # Logs every privileged call and keeps what tee would have written.
  mock_bin sudo <<'EOF'
#!/bin/bash
mock_log "sudo $*"
[ "$1" = tee ] && cat >"$MOCK_DIR/wrote-$(basename "$2")"
exit 0
EOF
  mock_bin ohmydebn-ai-set-default <<'EOF'
#!/bin/bash
mock_log "ai-set-default $*"
EOF
  cp "$FINGERPRINT_SCRIPT" "$MOCK_BIN/ohmydebn-pgp-fingerprint"
  for script in install remove; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/ohmydebn-claude-desktop-$script" >"$MOCK_DIR/$script.sh"
  done
}
run() { PATH="$(mock_path)" bash "$@" 2>&1; }
line_of() { grep -n -F -m1 "$1" "$MOCK_CALLS" | cut -d: -f1; }

setup
OUT=$(run "$MOCK_DIR/install.sh" <<<"")
STATUS=$?
CALLS=$(cat "$MOCK_CALLS")
assert_eq "install: succeeds" "0" "$STATUS"
assert_contains "install: asks first" "$OUT" "Press Enter to continue or Ctrl-C to cancel."
assert_contains "install: the key comes from Anthropic" "$CALLS" "curl -fsSL https://downloads.claude.ai/claude-desktop/key.asc"
assert_contains "install: the checked key is installed for apt" "$CALLS" "sudo install -D -m 0644"
assert_contains "install: ...as the keyring the package uses" "$CALLS" "/usr/share/keyrings/claude-desktop-archive-keyring.asc"
assert_eq "install: the sources file starts with the package's marker, so the package manages it" \
  "### Managed by the claude-desktop package." "$(head -n1 "$MOCK_DIR/wrote-claude-desktop.list")"
assert_contains "install: the repository, signed by that key" "$(cat "$MOCK_DIR/wrote-claude-desktop.list")" \
  "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main"
PIN=$(cat "$MOCK_DIR/wrote-claude-desktop.pref")
assert_contains "install: pin refuses everything else from the host" "$PIN" $'Package: *\nPin: origin "downloads.claude.ai"\nPin-Priority: -1'
assert_contains "install: pin allows claude-desktop" "$PIN" $'Package: claude-desktop\nPin: origin "downloads.claude.ai"\nPin-Priority: 500'
assert_eq "install: apt update after the repo and pin, before the install" "yes" \
  "$([ "$(line_of 'tee /etc/apt/preferences.d/claude-desktop.pref')" -lt "$(line_of 'sudo /usr/bin/apt update')" ] &&
    [ "$(line_of 'sudo /usr/bin/apt update')" -lt "$(line_of 'sudo /usr/bin/apt -y install claude-desktop')" ] && echo yes || echo no)"
assert_contains "install: then asks about the default AI" "$CALLS" "ai-set-default --ask claude-desktop"
mock_cleanup

# A key that isn't Anthropic's: refused before anything is changed
setup
OUT=$(MOCK_KEY=bad run "$MOCK_DIR/install.sh" <<<"")
STATUS=$?
assert_eq "wrong key: fails" "1" "$STATUS"
assert_contains "wrong key: says why" "$OUT" "isn't the one Anthropic publishes, so it wasn't installed"
assert_not_contains "wrong key: nothing privileged runs" "$(cat "$MOCK_CALLS")" "sudo"
mock_cleanup

# An architecture Anthropic doesn't build for: refused, nothing downloaded
setup
OUT=$(MOCK_ARCH=armhf run "$MOCK_DIR/install.sh" <<<"")
STATUS=$?
assert_eq "armhf: fails" "1" "$STATUS"
assert_contains "armhf: says which architectures" "$OUT" "only available for x86_64 and arm64"
assert_eq "armhf: nothing downloaded or changed" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# arm64 is fine
setup
MOCK_ARCH=arm64 run "$MOCK_DIR/install.sh" <<<"" >/dev/null
assert_contains "arm64: installs" "$(cat "$MOCK_CALLS")" "sudo /usr/bin/apt -y install claude-desktop"
mock_cleanup

# --skip-prompt: no question, no default-AI question
setup
OUT=$(run "$MOCK_DIR/install.sh" --skip-prompt </dev/null)
assert_not_contains "--skip-prompt: doesn't ask" "$OUT" "Press Enter"
assert_contains "--skip-prompt: installs" "$(cat "$MOCK_CALLS")" "apt -y install claude-desktop"
assert_not_contains "--skip-prompt: no default-AI question" "$(cat "$MOCK_CALLS")" "ai-set-default"
mock_cleanup

# Already installed: nothing
setup
MOCK_INSTALLED=1 run "$MOCK_DIR/install.sh" </dev/null >/dev/null
assert_eq "already installed: nothing runs" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- the remove script ---
setup
OUT=$(MOCK_INSTALLED=1 run "$MOCK_DIR/remove.sh" <<<"")
CALLS=$(cat "$MOCK_CALLS")
assert_contains "remove: asks first" "$OUT" "Continuing will remove Claude Desktop and its repo."
assert_contains "remove: purges the package (its postrm drops the repo it manages)" "$CALLS" "sudo /usr/bin/apt -y purge claude-desktop"
assert_contains "remove: our pin goes" "$CALLS" "sudo rm -f /etc/apt/preferences.d/claude-desktop.pref"
assert_contains "remove: a leftover repo entry goes" "$CALLS" "sudo rm -f /etc/apt/sources.list.d/claude-desktop.list"
assert_contains "remove: a leftover key goes" "$CALLS" "sudo rm -f /usr/share/keyrings/claude-desktop-archive-keyring.asc"
assert_eq "remove: apt update after the repo is gone" "yes" \
  "$([ "$(line_of 'claude-desktop.pref')" -lt "$(line_of 'sudo /usr/bin/apt update')" ] && echo yes || echo no)"
mock_cleanup

setup
MOCK_INSTALLED=1 run "$MOCK_DIR/remove.sh" --skip-prompt </dev/null >/dev/null
assert_contains "remove --skip-prompt: removes without asking" "$(cat "$MOCK_CALLS")" "purge claude-desktop"
mock_cleanup

setup
OUT=$(run "$MOCK_DIR/remove.sh" </dev/null)
assert_contains "remove, not installed: says so" "$OUT" "Claude Desktop is not currently installed."
assert_eq "remove, not installed: nothing runs" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

test_summary
