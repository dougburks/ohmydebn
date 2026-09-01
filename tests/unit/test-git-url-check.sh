#!/bin/bash
#
# Unit tests for bin/ohmydebn-git-url-check, the shared validator ported
# from omarchy's own "refuse the git transports we don't clone from" fix.
# It has two jobs: refuse anything shaped like a git option or a
# `<helper>::<address>` transport helper outright, and for anything shaped
# like `<scheme>://<address>`, only accept schemes git itself connects
# with - refusing helper-backed schemes like `ext://` or `fd://` even
# though they don't contain '::' and so wouldn't be caught by the first
# check alone.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-git-url-check"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-git-url-check ==="

check() {
  bash "$SCRIPT" "$1" >/dev/null 2>&1
}

mock_init

for url in "-x" "--upload-pack=touch /tmp/pwned" "ext::sh -c id" "fd::0,1" "gcrypt::rsync://x"; do
  if check "$url"; then
    assert_eq "rejects '$url'" "rejected" "accepted"
  else
    assert_eq "rejects '$url'" "rejected" "rejected"
  fi
done

for url in "ext://evil" "fd://0" "weird://evil"; do
  if check "$url"; then
    assert_eq "rejects unlisted transport '$url'" "rejected" "accepted"
  else
    assert_eq "rejects unlisted transport '$url'" "rejected" "rejected"
  fi
done

for url in \
  "https://github.com/foo/bar.git" \
  "http://example.com/repo.git" \
  "git://example.com/repo.git" \
  "git+ssh://example.com/repo.git" \
  "ssh+git://example.com/repo.git" \
  "ftp://example.com/repo.git" \
  "ftps://example.com/repo.git" \
  "file:///home/user/repo.git" \
  "git@github.com:foo/bar.git" \
  "git@[2001:db8::1]:org/repo.git" \
  "/home/user/local-repo"; do
  if check "$url"; then
    assert_eq "accepts '$url'" "accepted" "accepted"
  else
    assert_eq "accepts '$url'" "accepted" "rejected"
  fi
done

check ""
assert_eq "rejects an empty URL" "1" "$?"

mock_cleanup
test_summary
