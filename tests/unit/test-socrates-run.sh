#!/bin/bash
#
# Unit tests for bin/ohmydebn-socrates-run. SO-CRATES is published on
# 127.0.0.1 only: nothing else on the network needs it, and it shows the
# user's packet captures. Before 4.9.0 it was published on every interface
# and wrote pasta_options = ["-4"] into ~/.config/containers/containers.conf
# (so "localhost" over ::1 wouldn't hang), which turned off IPv6 in every
# rootless container the user runs. It must no longer write that file, and
# must leave a line from an older release alone. On a desktop it opens the
# web interface by itself once SO-CRATES answers.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-socrates-run"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-socrates-run ==="

setup_mocks() {
  mock_bin podman <<'EOF'
#!/bin/bash
echo "podman $*" >>"$MOCK_CALLS"
exit 0
EOF
  mock_bin ohmydebn-socrates-cleanup <<'EOF'
#!/bin/bash
echo "ohmydebn-socrates-cleanup $*" >>"$MOCK_CALLS"
exit 0
EOF
  mock_bin ohmydebn-podman-subids-ensure <<'EOF'
#!/bin/bash
echo "ohmydebn-podman-subids-ensure $*" >>"$MOCK_CALLS"
exit 0
EOF
  # Nothing answers on the port unless a scenario says so: the real curl
  # would ask whatever is on this computer's port 8000.
  mock_bin curl <<'EOF'
#!/bin/bash
echo "curl $*" >>"$MOCK_CALLS"
[[ -e "$MOCK_DIR/answering" ]]
EOF
  mock_bin xdg-open <<'EOF'
#!/bin/bash
echo "xdg-open $*" >>"$MOCK_CALLS"
EOF
  # The real setsid -f returns before xdg-open has run, racing the asserts.
  mock_bin setsid <<'EOF'
#!/bin/bash
[[ "$1" == "-f" ]] && shift
exec "$@"
EOF
  sed -e "s#/usr/bin/podman#$MOCK_BIN/podman#" \
    -e "s#/usr/bin/curl#$MOCK_BIN/curl#" \
    -e "s#/usr/bin/xdg-open#$MOCK_BIN/xdg-open#" \
    -e "s#sleep 2\$#sleep 0.1#" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-socrates-cleanup#$MOCK_BIN/ohmydebn-socrates-cleanup#" \
    -e "s#/usr/share/ohmydebn/bin/ohmydebn-podman-subids-ensure#$MOCK_BIN/ohmydebn-podman-subids-ensure#" \
    "$SCRIPT" >"$MOCK_DIR/socrates-run-patched.sh"
}

# Runs the patched script end-to-end (real podman/cleanup calls stubbed
# out, `read -r` at the end fed EOF via /dev/null so it returns instead of
# hanging), with no desktop unless DISPLAY is given as an argument.
run_socrates() {
  env -u DISPLAY -u WAYLAND_DISPLAY HOME="$SCRATCH_HOME" PATH="$(mock_path)" "$@" \
    bash "$MOCK_DIR/socrates-run-patched.sh" </dev/null >/dev/null 2>&1
}

# A podman that brings SO-CRATES up a moment after it starts, then runs
# until it's stopped a moment later.
mock_podman_answers() {
  mock_bin podman <<'EOF'
#!/bin/bash
echo "podman $*" >>"$MOCK_CALLS"
sleep 0.3
touch "$MOCK_DIR/answering"
sleep 1
rm -f "$MOCK_DIR/answering"
exit 0
EOF
}

CONF_REL=".config/containers/containers.conf"

# Scenario 1: published on this computer only.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_socrates
assert_contains "port 8000 published on 127.0.0.1 only" "$(cat "$MOCK_CALLS")" "-p 127.0.0.1:8000:8000"
assert_not_contains "not published on every interface" "$(cat "$MOCK_CALLS")" "-p 8000:8000"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 2: no containers.conf -> none is created.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_socrates
assert_eq "no containers.conf is written" "no" "$([[ -e "$SCRATCH_HOME/$CONF_REL" ]] && echo yes || echo no)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 3: the -4 line an older release wrote -> left exactly as it is.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.config/containers"
printf '\n[network]\npasta_options = ["-4"]\n' >"$SCRATCH_HOME/$CONF_REL"
BEFORE=$(cat "$SCRATCH_HOME/$CONF_REL")
run_socrates
assert_eq "an existing containers.conf is left alone" "$BEFORE" "$(cat "$SCRATCH_HOME/$CONF_REL")"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 6: the subordinate-ID backfill runs, and runs before podman -
# it exists to fix the pull, so after would be useless.
mock_init
setup_mocks
SCRATCH_HOME=$(mktemp -d)
run_socrates
CALLS=$(cat "$MOCK_CALLS")
assert_contains "subids-ensure invoked" "$CALLS" "ohmydebn-podman-subids-ensure"
assert_eq "subids-ensure runs before podman" "ohmydebn-podman-subids-ensure" "$(head -n1 "$MOCK_CALLS" | cut -d' ' -f1)"
assert_contains "the container is removed when SO-CRATES stops (--rm)" "$(grep 'podman run' "$MOCK_CALLS")" " --rm "
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 7: the backfill failed (its sudo declined, say) -> podman never
# runs; the pull would only die with the lchown error the backfill prevents.
mock_init
setup_mocks
mock_bin ohmydebn-podman-subids-ensure <<'EOF'
#!/bin/bash
echo "ohmydebn-podman-subids-ensure $*" >>"$MOCK_CALLS"
exit 1
EOF
SCRATCH_HOME=$(mktemp -d)
OUTPUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_DIR/socrates-run-patched.sh" </dev/null 2>&1)
STATUS=$?
assert_not_contains "failed subids backfill: podman not run" "$(cat "$MOCK_CALLS")" "podman run"
assert_contains "failed subids backfill: says why" "$OUTPUT" "subordinate UID/GID ranges"
assert_eq "failed subids backfill: exits non-zero" "1" "$STATUS"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 8: podman exits non-zero (SO-CRATES stopped with Ctrl-C, or a
# failed pull) -> the cleanup still runs and the script ends normally.
mock_init
setup_mocks
mock_bin podman <<'EOF'
#!/bin/bash
echo "podman $*" >>"$MOCK_CALLS"
exit 130
EOF
SCRATCH_HOME=$(mktemp -d)
run_socrates
STATUS=$?
assert_contains "podman stopped: cleanup still runs" "$(cat "$MOCK_CALLS")" "ohmydebn-socrates-cleanup"
assert_eq "podman stopped: script ends normally" "0" "$STATUS"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 9: on a desktop, the browser opens on SO-CRATES once it answers,
# and only once.
mock_init
setup_mocks
mock_podman_answers
SCRATCH_HOME=$(mktemp -d)
run_socrates DISPLAY=:0
assert_eq "desktop: browser opened once" "1" "$(grep -c '^xdg-open' "$MOCK_CALLS")"
assert_contains "desktop: browser opened on SO-CRATES" "$(cat "$MOCK_CALLS")" "xdg-open http://127.0.0.1:8000/"
assert_eq "desktop: opened after podman started" "podman" "$(grep -E '^(podman|xdg-open)' "$MOCK_CALLS" | head -n1 | cut -d' ' -f1)"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 10: Wayland counts as a desktop too.
mock_init
setup_mocks
mock_podman_answers
SCRATCH_HOME=$(mktemp -d)
run_socrates WAYLAND_DISPLAY=wayland-0
assert_contains "Wayland: browser opened" "$(cat "$MOCK_CALLS")" "xdg-open http://127.0.0.1:8000/"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 11: no desktop (over SSH, say) -> no browser, nothing asked.
mock_init
setup_mocks
mock_podman_answers
SCRATCH_HOME=$(mktemp -d)
run_socrates
assert_not_contains "no desktop: no browser" "$(cat "$MOCK_CALLS")" "xdg-open"
assert_not_contains "no desktop: port not probed" "$(cat "$MOCK_CALLS")" "curl"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 12: something already answers on the port -> podman can't
# publish it, and the browser would show that instead: none opened.
mock_init
setup_mocks
touch "$MOCK_DIR/answering"
SCRATCH_HOME=$(mktemp -d)
run_socrates DISPLAY=:0
assert_not_contains "port already taken: no browser" "$(cat "$MOCK_CALLS")" "xdg-open"
rm -rf "$SCRATCH_HOME"
mock_cleanup

# Scenario 13: SO-CRATES never answers (a failed pull) -> no browser, and
# the wait stops with podman instead of probing on behind the window.
mock_init
setup_mocks
mock_bin podman <<'EOF'
#!/bin/bash
echo "podman $*" >>"$MOCK_CALLS"
sleep 0.5
exit 125
EOF
SCRATCH_HOME=$(mktemp -d)
START=$SECONDS
# A wait that isn't stopped holds the script open: cut it off to fail.
run_socrates DISPLAY=:0 timeout 10
assert_eq "never answers: script ends with podman" "yes" "$([[ $((SECONDS - START)) -le 3 ]] && echo yes || echo no)"
PROBES=$(grep -c '^curl' "$MOCK_CALLS")
sleep 0.5
assert_eq "never answers: probing stopped" "$PROBES" "$(grep -c '^curl' "$MOCK_CALLS")"
assert_not_contains "never answers: no browser" "$(cat "$MOCK_CALLS")" "xdg-open"
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
