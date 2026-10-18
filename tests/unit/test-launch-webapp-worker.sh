#!/bin/bash
#
# Unit tests for bin/ohmydebn-launch-webapp-worker, which opens a web app
# as an app window in the default browser (--app= for the Chromium family,
# --kiosk for Firefox), and with xdg-open for any other browser - or for a
# default that names a browser that's since been removed, which used to
# run a missing command and open nothing.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-launch-webapp-worker"
BASH_BIN="$(command -v bash)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-launch-webapp-worker ==="

mock_init
URL="https://example.com/?a=1&b=2"

# A logging stand-in for each command the worker may run.
for cmd in firefox chromium google-chrome-stable brave-origin brave-browser helium xdg-open; do
  mock_bin "$cmd" <<EOF2
#!/bin/bash
echo "$cmd \$*" >>"\$MOCK_CALLS"
EOF2
done

# run_worker <default browser id>: only the mocks on PATH, so the real
# system's browsers can't be found.
run_worker() {
  : >"$MOCK_CALLS"
  mock_bin xdg-settings <<EOF2
#!/bin/bash
echo "$1"
EOF2
  PATH="$MOCK_BIN" "$BASH_BIN" "$SCRIPT" "$URL" >/dev/null 2>&1
  cat "$MOCK_CALLS"
}

assert_eq "Firefox: kiosk window" "firefox --kiosk $URL" "$(run_worker firefox-esr.desktop)"
assert_eq "Chromium: app window" "chromium --app=$URL" "$(run_worker chromium.desktop)"
assert_eq "Chrome: app window" "google-chrome-stable --app=$URL" "$(run_worker google-chrome.desktop)"
assert_eq "Brave Origin: its own binary" "brave-origin --app=$URL" "$(run_worker brave-origin.desktop)"
assert_eq "Brave: its own binary" "brave-browser --app=$URL" "$(run_worker brave-browser.desktop)"
assert_eq "Helium: app window" "helium --app=$URL" "$(run_worker net.imput.helium.desktop)"
assert_eq "another browser: xdg-open" "xdg-open $URL" "$(run_worker org.qutebrowser.qutebrowser.desktop)"
assert_eq "no default at all: xdg-open" "xdg-open $URL" "$(run_worker "")"

rm "$MOCK_BIN/brave-origin"
assert_eq "a removed default browser: xdg-open instead of nothing" "xdg-open $URL" "$(run_worker brave-origin.desktop)"

mock_cleanup
test_summary
