#!/bin/bash
#
# Unit tests for bin/ohmydebn-menu's persistent-picker mechanism
# (start_persistent_picker/stop_persistent_picker/get_picker_result,
# wired into menu() in place of a fresh ohmydebn-menu-picker spawn per
# call). Everything else in ohmydebn-menu - every show_*_menu's own
# dispatch, the search-jump-queue splitting in menu() itself - is
# unchanged and already covered elsewhere; this only exercises the new
# request/response mechanism: reuse across calls, the request line format,
# and the fallback-to-one-shot path when the picker can't be started or
# stops answering.
#
# Uses a mock ohmydebn-menu-picker (bash, implementing just enough of the
# real --serve protocol to drive these scenarios) rather than the real GTK
# one - faster, deterministic, and lets a mid-session "picker crashed"
# scenario be simulated directly, which isn't practical against the real
# process in an automated test.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MENU_SCRIPT="$REPO_ROOT/bin/ohmydebn-menu"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-menu persistent picker ==="

# Strips the trailing "if [[ -n \"\${1:-}\" ]]; then go_to_menu ...; else
# show_main_menu; fi" dispatch block so sourcing this file only defines
# functions - doesn't immediately try to show a real menu.
strip_dispatch() {
  sed '/^if \[\[ -n "\${1:-}"/,$d' "$1"
}

setup_mock_picker() {
  mock_bin ohmydebn-menu-picker <<'EOF'
#!/bin/bash
# Mock --serve implementation: answers requests in order from
# $MOCK_RESPONSES_FILE (one line per request), logging each request's
# breadcrumb to $MOCK_CALLS. Exits its serve loop on QUIT or when a
# response file line is literally "CRASH" (simulates the picker dying
# mid-session, without a graceful QUIT ever being read back); a line of
# "SLOW" logs the request and then just sleeps well past this test's own
# timeout, without ever replying (simulates a real, long human decision -
# what the signal-interruptibility test below needs, since that's exactly
# the condition that used to make an external TERM/INT wait for the
# picker instead of being handled promptly).
if [[ "$1" == "--serve" ]]; then
  req="$2"; resp="$3"
  echo "serve-start" >>"$MOCK_CALLS"
  if [[ "${MOCK_SERVE_FAILS_TO_START:-}" == "1" ]]; then
    exit 1
  fi
  exec 4>"$resp"
  exec 3<"$req"
  while IFS=$'\t' read -r -u 3 breadcrumb options; do
    if [[ "$breadcrumb" == "QUIT" && -z "$options" ]]; then
      echo "serve-quit" >>"$MOCK_CALLS"
      break
    fi
    echo "serve-request:$breadcrumb" >>"$MOCK_CALLS"
    reply=$(head -n1 "$MOCK_RESPONSES_FILE")
    tail -n +2 "$MOCK_RESPONSES_FILE" >"$MOCK_RESPONSES_FILE.tmp"
    mv "$MOCK_RESPONSES_FILE.tmp" "$MOCK_RESPONSES_FILE"
    if [[ "$reply" == "CRASH" ]]; then
      echo "serve-crash" >>"$MOCK_CALLS"
      exit 1
    fi
    if [[ "$reply" == "SLOW" ]]; then
      echo "serve-slow" >>"$MOCK_CALLS"
      sleep 60
      continue
    fi
    echo "$reply" >&4
  done
  exit 0
else
  echo "oneshot-called:$2" >>"$MOCK_CALLS"
  reply=$(head -n1 "$MOCK_RESPONSES_FILE")
  tail -n +2 "$MOCK_RESPONSES_FILE" >"$MOCK_RESPONSES_FILE.tmp"
  mv "$MOCK_RESPONSES_FILE.tmp" "$MOCK_RESPONSES_FILE"
  echo "$reply"
fi
EOF
  # ohmydebn-menu-tree also needs redirecting here, separately from the
  # picker mock above - it's not mocked, but menu() calls its
  # menu_tree_paths() (for the breadcrumb-prefix lookup) against
  # $MOCK_DIR/menu-functions.sh's own content, and the real, unpatched
  # system copy still parses for the pre-this-change
  # `case $(menu "Title" "items") in` shape, which no longer exists
  # anywhere in this repo's own (edited) ohmydebn-menu - confirmed the
  # hard way: sourcing only patched the picker reference here at first,
  # and every menu_tree_paths() call silently came back wrong.
  sed -e "s#/usr/share/ohmydebn/bin/ohmydebn-menu-picker#$MOCK_BIN/ohmydebn-menu-picker#g" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-menu-tree#$REPO_ROOT/bin/ohmydebn-menu-tree#g" \
    <(strip_dispatch "$MENU_SCRIPT") >"$MOCK_DIR/menu-functions.sh"
}

set_responses() {
  printf '%s\n' "$@" >"$RESPONSES_FILE"
}

# --- Reuse across calls: two picks in one session share one picker process ---
mock_init
setup_mock_picker
RESPONSES_FILE="$MOCK_DIR/responses"
set_responses "Install" "AI"

(
  PATH="$(mock_path):$PATH"
  export MOCK_CALLS PATH MOCK_RESPONSES_FILE="$RESPONSES_FILE"
  set +u
  source "$MOCK_DIR/menu-functions.sh"
  set -u
  menu "Go" "some items"
  first="$MENU_RESULT"
  menu "Install" "some items"
  second="$MENU_RESULT"
  printf 'RESULTS:%s|%s\n' "$first" "$second" >>"$MOCK_CALLS"
)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "picker started exactly once across two picks" "1" "$(grep -c '^serve-start$' <<<"$CALLS")"
assert_contains "first pick's request reaches the picker" "$CALLS" "serve-request:"
assert_contains "both picks returned correctly" "$CALLS" "RESULTS:Install|AI"
assert_contains "session end sends QUIT" "$CALLS" "serve-quit"

# --- Request line format: breadcrumb and options are tab-separated, in order ---
mock_init
setup_mock_picker
RESPONSES_FILE="$MOCK_DIR/responses"
set_responses "SomeAI"
(
  PATH="$(mock_path):$PATH"
  export MOCK_CALLS PATH MOCK_RESPONSES_FILE="$RESPONSES_FILE"
  set +u
  source "$MOCK_DIR/menu-functions.sh"
  set -u
  get_picker_result "Item One\nItem Two" "Install > AI"
)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "breadcrumb prefix is sent as given" "$CALLS" "serve-request:Install > AI"

# --- Fallback: picker fails to start entirely -> one-shot mode still answers ---
mock_init
setup_mock_picker
RESPONSES_FILE="$MOCK_DIR/responses"
set_responses "FallbackPick"
(
  PATH="$(mock_path):$PATH"
  export MOCK_CALLS PATH MOCK_RESPONSES_FILE="$RESPONSES_FILE" MOCK_SERVE_FAILS_TO_START=1
  set +u
  source "$MOCK_DIR/menu-functions.sh"
  set -u
  get_picker_result "items" ""
  printf 'RESULT:%s\n' "$MENU_PICKER_RESULT" >>"$MOCK_CALLS"
)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "unstartable picker falls back to one-shot mode" "$CALLS" "oneshot-called:"
assert_contains "fallback still returns the picked value" "$CALLS" "RESULT:FallbackPick"

# --- Fallback: picker dies mid-session -> that call, and every later one
# this session, still gets a real answer via one-shot mode instead of
# hanging. get_picker_result deliberately never tries to restart the
# persistent picker itself (see its own comment: kept out on purpose, to
# keep the signal-handling fix that made this safe to do a contained
# change) - once it's gone, one-shot mode is used for the rest of the
# session, not just once.
mock_init
setup_mock_picker
RESPONSES_FILE="$MOCK_DIR/responses"
set_responses "FirstOK" "CRASH" "AfterCrash1" "AfterCrash2"
(
  PATH="$(mock_path):$PATH"
  export MOCK_CALLS PATH MOCK_RESPONSES_FILE="$RESPONSES_FILE"
  set +u
  source "$MOCK_DIR/menu-functions.sh"
  set -u
  get_picker_result "items" ""
  first="$MENU_PICKER_RESULT"
  get_picker_result "items" ""
  second="$MENU_PICKER_RESULT"
  get_picker_result "items" ""
  third="$MENU_PICKER_RESULT"
  printf 'RESULTS:%s|%s|%s\n' "$first" "$second" "$third" >>"$MOCK_CALLS"
)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "picker crash is observed" "$CALLS" "serve-crash"
assert_contains "the call during the crash still gets a real answer, not a hang" "$CALLS" "RESULTS:FirstOK|AfterCrash1|AfterCrash2"
assert_eq "no attempt to restart the persistent picker after it's gone" "1" "$(grep -c '^serve-start$' <<<"$CALLS")"
assert_eq "both post-crash calls used one-shot mode" "2" "$(grep -c '^oneshot-called:' <<<"$CALLS")"

# --- The actual point of this whole change: an external TERM sent while
# blocked on a real (here, simulated-slow) human decision is handled
# promptly, not deferred until that decision would have completed. This
# is the one thing the mock-protocol tests above can't exercise - they
# never leave get_picker_result's `wait` blocked long enough for a signal
# to matter - and it's the specific thing confirmed broken, then fixed, by
# hand earlier: a script blocked in `x=$(sleep 30)` never ran its TERM
# trap at all; the same script blocked in `sleep 30 & wait $!` ran it
# within about a second. menu()/get_picker_result's whole call chain was
# restructured (no more `case $(menu ...) in`, see menu()'s own comment)
# specifically so this script's real "wait for a pick" is the latter, not
# the former - this test is what would catch a regression back to the
# former.
mock_init
setup_mock_picker
RESPONSES_FILE="$MOCK_DIR/responses"
set_responses "SLOW"

driver="$MOCK_DIR/driver.sh"
cat >"$driver" <<DRIVER
#!/bin/bash
set +u
source "$MOCK_DIR/menu-functions.sh"
set -u
menu "Test" "items"
echo "REACHED_END_UNKILLED" >>"\$MOCK_CALLS"
DRIVER
chmod +x "$driver"

PATH="$(mock_path):$PATH" MOCK_CALLS="$MOCK_CALLS" MOCK_RESPONSES_FILE="$RESPONSES_FILE" \
  bash "$driver" &
driver_pid=$!

# Wait for the mock to actually log that it's in the middle of the slow
# (60s) request - only then is get_picker_result guaranteed to already be
# blocked in its `wait`, which is the exact state this test needs to catch
# a regression in.
for _ in $(seq 1 100); do
  grep -q '^serve-slow$' "$MOCK_CALLS" 2>/dev/null && break
  sleep 0.05
done

start_ts=$(date +%s.%N)
kill -TERM "$driver_pid"

killed=0
for _ in $(seq 1 100); do
  kill -0 "$driver_pid" 2>/dev/null || {
    killed=1
    break
  }
  sleep 0.05
done
end_ts=$(date +%s.%N)
elapsed=$(awk -v a="$start_ts" -v b="$end_ts" 'BEGIN{printf "%.2f", b-a}')

assert_eq "TERM sent mid-request is handled promptly, not deferred ~60s" "1" "$killed"
# A loose but meaningful bound: prompt handling is confirmed at ~1s by
# hand (see the comment above); 10s leaves headroom for slower CI
# machines without coming anywhere close to the 60s mock sleep or the
# 300s real read timeout it would otherwise take to notice.
awk -v e="$elapsed" 'BEGIN{exit !(e < 10)}'
assert_eq "elapsed time is small (${elapsed}s), not deferred until the slow request would finish" "0" "$?"

wait "$driver_pid" 2>/dev/null
assert_not_contains "the script never reached past its blocked menu() call" "$(cat "$MOCK_CALLS")" "REACHED_END_UNKILLED"

# The mock --serve process is this driver's own child, in its own process
# group - `kill -- -$$` in the TERM trap should have taken it down too,
# not just the driver itself, or it leaks exactly like the very orphan
# this whole change exists to prevent.
sleep 0.2
remaining=$(pgrep -f "ohmydebn-menu-picker.*--serve" 2>/dev/null | while read -r pid; do
  cmdline=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
  case "$cmdline" in *"$MOCK_BIN"*) echo "$pid" ;; esac
done)
assert_eq "the mock picker process is also cleaned up, not left orphaned" "" "$remaining"
[[ -n "$remaining" ]] && kill -9 $remaining 2>/dev/null

mock_cleanup
test_summary
