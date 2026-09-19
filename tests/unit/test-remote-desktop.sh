#!/bin/bash
#
# Unit tests for the Remote Desktop (XRDP) scripts: ohmydebn-remote-desktop-server
# (menu launcher), -install, -remove, ohmydebn-xrdp-session-guard with its
# Xsession.d drop-in (config/xrdp/), and ohmydebn-firewall-hint. The
# Xsession.d directory and systemd signal directory are sed-patched into a
# scratch root; sudo runs its command for real against those paths except
# apt/systemctl/service/adduser, which are only logged; dpkg answers from
# MOCK_INSTALLED; loginctl answers from a session table the guard tests
# write.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-remote-desktop-server / -install / -remove / ohmydebn-xrdp-session-guard / ohmydebn-firewall-hint ==="

setup() {
  mock_init
  ROOT="$MOCK_DIR/root"; H="$MOCK_DIR/home"
  mkdir -p "$ROOT/etc/X11/Xsession.d" "$H"
  [ "${MOCK_SYSTEMD:-true}" = true ] && mkdir -p "$ROOT/run/systemd/system"
  mock_bin dpkg <<'EOF2'
#!/bin/bash
[[ "$1" == "-s" && " ${MOCK_INSTALLED:-} " == *" $2 "* ]] && exit 0
exit 1
EOF2
  mock_bin sudo <<'EOF2'
#!/bin/bash
mock_log "sudo $*"
case "$1" in
/usr/bin/apt | systemctl | service | adduser) exit 0 ;;
esac
exec "$@"
EOF2
  mock_bin getent <<'EOF2'
#!/bin/bash
[[ "$1" == group && "$2" == ssl-cert ]] && { echo "ssl-cert:x:106:"; exit 0; }
exit 2
EOF2
  mock_bin id <<'EOF2'
#!/bin/bash
# `id xrdp` (exists?) and `id -nG xrdp` (groups); MOCK_XRDP_GROUPS lists them.
[[ "$1" == "-nG" ]] && { echo "${MOCK_XRDP_GROUPS:-xrdp}"; exit 0; }
[[ "$1" == xrdp ]] && exit 0
exit 1
EOF2
  mock_bin hostname <<'EOF2'
#!/bin/bash
echo "192.0.2.10 fd00::10"
EOF2
  mock_bin ufw <<'EOF2'
#!/bin/bash
mock_log "ufw $*"
EOF2
  for name in ohmydebn-launch-floating-terminal ohmydebn-launch-floating-terminal-with-presentation; do
    mock_bin "$name" <<EOF2
#!/bin/bash
echo "$name \$*" >>"\$MOCK_CALLS"
EOF2
  done
  for script in ohmydebn-remote-desktop-server ohmydebn-remote-desktop-server-install ohmydebn-remote-desktop-server-remove ohmydebn-xrdp-session-guard ohmydebn-firewall-hint; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#^GUARD=.*#GUARD=$ROOT/etc/X11/Xsession.d/45ohmydebn-xrdp-session-guard#; s#^SYSTEMD_DIR=.*#SYSTEMD_DIR=$ROOT/run/systemd/system#; s#^XSESSION_D=.*#XSESSION_D=$ROOT/etc/X11/Xsession.d#; s#^GUARD_SRC=.*#GUARD_SRC=$REPO_ROOT/config/xrdp/45ohmydebn-xrdp-session-guard#" \
      "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
  DROPIN="$ROOT/etc/X11/Xsession.d/45ohmydebn-xrdp-session-guard"
}
run() { HOME="$H" PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" MOCK_XRDP_GROUPS="${MOCK_XRDP_GROUPS:-xrdp}" bash "$@" </dev/null 2>&1; }

# --- install, fresh, systemd: packages, TLS group, PAM guard, ~/.xsession, service, no firewall rule ---
setup
OUT=$(MOCK_INSTALLED="" run "$MOCK_BIN/ohmydebn-remote-desktop-server-install" --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "fresh: installs xrdp and xorgxrdp" "$CALLS" "sudo /usr/bin/apt -y install xrdp xorgxrdp"
assert_contains "fresh: xrdp user added to ssl-cert for the TLS key" "$CALLS" "sudo adduser xrdp ssl-cert"
assert_eq "fresh: Xsession.d drop-in installed, world-readable, identical to the shipped file" "yes" \
  "$([ "$(stat -c %a "$DROPIN")" = 644 ] && cmp -s "$DROPIN" "$REPO_ROOT/config/xrdp/45ohmydebn-xrdp-session-guard" && echo yes || echo no)"
assert_eq "fresh: no ~/.xsession written" "no" "$([ -e "$H/.xsession" ] && echo yes || echo no)"
assert_contains "fresh: service enabled under systemd" "$CALLS" "sudo systemctl enable --now xrdp"
assert_not_contains "fresh: no firewall rule added" "$CALLS" "ufw allow"
assert_contains "fresh: firewall guidance printed for 3389" "$OUT" "sudo ufw allow from 192.168.1.0/24 to any port 3389 proto tcp comment 'OhMyDebn Remote Desktop Server'"
assert_contains "fresh: address shown" "$OUT" "192.0.2.10:3389"
mock_cleanup

# --- install again, everything already in place: idempotent ---
setup
run "$MOCK_BIN/ohmydebn-remote-desktop-server-install" --skip-prompt >/dev/null
: >"$MOCK_CALLS"
OUT=$(MOCK_INSTALLED="xrdp" MOCK_XRDP_GROUPS="xrdp ssl-cert" run "$MOCK_BIN/ohmydebn-remote-desktop-server-install" --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "rerun: no apt" "$CALLS" "apt"
assert_not_contains "rerun: adduser skipped when already a member" "$CALLS" "adduser"
assert_eq "rerun: drop-in still the shipped file" "yes" "$(cmp -s "$DROPIN" "$REPO_ROOT/config/xrdp/45ohmydebn-xrdp-session-guard" && echo yes || echo no)"
assert_contains "rerun: tells a new user how to get their OhMyDebn desktop" "$OUT" "bash /usr/share/ohmydebn/install.sh"
mock_cleanup

# --- install with the user's own ~/.xsession: not our business, untouched ---
setup
printf '#!/bin/sh\nexec startxfce4\n' >"$H/.xsession"
MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-server-install" --skip-prompt >/dev/null
assert_eq "own xsession: file untouched" "#!/bin/sh
exec startxfce4" "$(cat "$H/.xsession")"
mock_cleanup

# --- install without systemd (Devuan/LCOS): service, not systemctl ---
MOCK_SYSTEMD=false setup
OUT=$(MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-server-install" --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "no systemd: systemctl never called" "$CALLS" "systemctl"
assert_contains "no systemd: service restart used" "$CALLS" "sudo service xrdp restart"
mock_cleanup

# --- install, prompt cancelled (EOF): nothing happens ---
setup
run "$MOCK_BIN/ohmydebn-remote-desktop-server-install" >/dev/null
EXIT_CODE=$?
assert_eq "cancelled at the prompt: exits non-zero" "1" "$EXIT_CODE"
assert_eq "cancelled at the prompt: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- menu launcher: not installed -> presentation with the installer; installed -> status window ---
setup
MOCK_INSTALLED="" run "$MOCK_BIN/ohmydebn-remote-desktop-server" >/dev/null
assert_contains "launcher, not installed: install presented" "$(cat "$MOCK_CALLS")" "ohmydebn-launch-floating-terminal-with-presentation Remote Desktop Server $MOCK_BIN/ohmydebn-remote-desktop-server-install"
mock_cleanup
setup
MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-server" >/dev/null
assert_contains "launcher, package present but guard missing: installer presented to configure it" "$(cat "$MOCK_CALLS")" "ohmydebn-launch-floating-terminal-with-presentation Remote Desktop"
mock_cleanup
setup
cp "$REPO_ROOT/config/xrdp/45ohmydebn-xrdp-session-guard" "$DROPIN"
MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-server" >/dev/null
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "launcher, installed and configured: no installer" "$CALLS" "with-presentation"
assert_contains "launcher, installed: status window with the address" "$CALLS" "192.0.2.10:3389"
assert_contains "launcher, installed: status command branches on systemd" "$CALLS" "if [ -d /run/systemd/system ]; then systemctl is-active xrdp; else service xrdp status; fi"
assert_contains "launcher, installed: firewall hint included" "$CALLS" "ohmydebn-firewall-hint 3389 'Remote Desktop Server'"
mock_cleanup

# --- remove: drop-in gone, service stopped, purged; firewall left alone ---
setup
run "$MOCK_BIN/ohmydebn-remote-desktop-server-install" --skip-prompt >/dev/null
: >"$MOCK_CALLS"
OUT=$(MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-server-remove" --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "remove: Xsession.d drop-in removed" "no" "$([ -e "$DROPIN" ] && echo yes || echo no)"
assert_contains "remove: service disabled" "$CALLS" "sudo systemctl disable --now xrdp xrdp-sesman"
assert_contains "remove: packages purged" "$CALLS" "sudo /usr/bin/apt -y purge xrdp xorgxrdp"
assert_not_contains "remove: no ufw change" "$CALLS" "ufw delete"
assert_contains "remove: user told how to drop their own rule" "$OUT" "sudo ufw delete"
mock_cleanup

# --- remove with the user's own ~/.xsession: never ours, kept ---
setup
printf '#!/bin/sh\nexec startxfce4\n' >"$H/.xsession"
MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-server-remove" --skip-prompt >/dev/null
assert_eq "remove, own xsession: kept" "yes" "$([ -f "$H/.xsession" ] && echo yes || echo no)"
mock_cleanup

# --- remove when not installed: says so, does nothing ---
setup
OUT=$(MOCK_INSTALLED="" run "$MOCK_BIN/ohmydebn-remote-desktop-server-remove" --skip-prompt)
assert_contains "remove, not installed: message" "$OUT" "not currently installed"
assert_eq "remove, not installed: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- the session guard: loginctl answers from a table the test writes ---
setup_guard() {
  setup
  mkdir -p "$MOCK_DIR/sessions"
  mock_bin loginctl <<'EOF2'
#!/bin/bash
# list-sessions --no-legend: the table in $MOCK_SESSION_TABLE (sid uid user seat tty)
# show-session <sid> -p <Prop> --value: from $MOCK_DIR/sessions/<sid> (Prop=value lines)
if [[ "$1" == list-sessions ]]; then cat "$MOCK_SESSION_TABLE"; exit 0; fi
if [[ "$1" == show-session ]]; then grep "^$4=" "$MOCK_DIR/sessions/$2" | cut -d= -f2; exit 0; fi
exit 1
EOF2
  mock_bin logger <<'EOF2'
#!/bin/bash
mock_log "logger $*"
EOF2
  export MOCK_SESSION_TABLE="$MOCK_DIR/sessions/table"
}
session() { # sid seat class state type
  printf 'Class=%s\nState=%s\nType=%s\n' "$3" "$4" "$5" >"$MOCK_DIR/sessions/$1"
}
run_guard() { USER="$1" PATH="$(mock_path)" MOCK_SESSION_TABLE="$MOCK_SESSION_TABLE" OHMYDEBN_XRDP_ALLOW_SHARED_USER="${2:-}" bash "$MOCK_BIN/ohmydebn-xrdp-session-guard" </dev/null >"$MOCK_DIR/guard-out" 2>/dev/null; echo $?; }

setup_guard
printf '2 1000 alice seat0 tty7\n' >"$MOCK_SESSION_TABLE"; session 2 seat0 user active x11
assert_eq "guard: user with a local x11 seat session is rejected" "1" "$(run_guard alice)"
assert_contains "guard: reason printed for the drop-in to show" "$(cat "$MOCK_DIR/guard-out")" "user 'alice' is already logged into the local desktop (session 2 on seat0)"
assert_contains "guard: rejection logged" "$(cat "$MOCK_CALLS")" "logger -t ohmydebn-xrdp-session-guard"
assert_eq "guard: a different user is allowed" "0" "$(run_guard bob)"
assert_eq "guard: override allows the same user" "0" "$(run_guard alice 1)"
mock_cleanup

setup_guard
printf '5 1000 alice - -\n7 1000 alice seat0 tty7\n' >"$MOCK_SESSION_TABLE"
session 5 - user active x11; session 7 seat0 user closing x11
assert_eq "guard: an existing remote session (no seat) and a closing local one don't block" "0" "$(run_guard alice)"
mock_cleanup

setup_guard
printf '3 1000 alice seat0 tty1\n' >"$MOCK_SESSION_TABLE"; session 3 seat0 user active tty
assert_eq "guard: a text console login on the seat doesn't block" "0" "$(run_guard alice)"
mock_cleanup

setup_guard
: >"$MOCK_SESSION_TABLE"
assert_eq "guard: no sessions at all -> allowed" "0" "$(run_guard alice)"
assert_eq "guard: no user at all -> allowed (nothing to check)" "0" "$(env -i PATH="$(mock_path)" MOCK_SESSION_TABLE="$MOCK_SESSION_TABLE" /bin/bash "$MOCK_BIN/ohmydebn-xrdp-session-guard" </dev/null >/dev/null 2>&1; echo $?)"
mock_cleanup

# --- the Xsession.d drop-in, sourced the way Xsession does (sh, set -e) ---
# The guard binary path inside it is patched to a stub whose verdict the
# test sets; the drop-in must end the session (exit 1) only for an XRDP
# session with a refusal, and must not disturb a local login at all.
setup_dropin() {
  setup
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/config/xrdp/45ohmydebn-xrdp-session-guard" >"$MOCK_DIR/dropin"
  mock_bin ohmydebn-xrdp-session-guard <<'EOF2'
#!/bin/bash
[[ -n "${MOCK_REFUSE:-}" ]] && { echo "refused: $MOCK_REFUSE"; exit 1; }
exit 0
EOF2
  # Logged straight to $MOCK_CALLS: the drop-in runs under dash, which
  # doesn't pass bash's exported mock_log function on to this stub.
  mock_bin xmessage <<'EOF2'
#!/bin/bash
echo "xmessage $*" >>"$MOCK_CALLS"
EOF2
  mock_bin loginctl <<'EOF2'
#!/bin/bash
[[ "$1" == show-session && "$4" == Seat ]] && { echo "${MOCK_SEAT:-}"; exit 0; }
exit 1
EOF2
}
# loginctl here answers only show-session -p Seat, from MOCK_SEAT.
run_dropin() { XRDP_SESSION="${1:-}" MOCK_REFUSE="${2:-}" XDG_SESSION_ID="${3:-}" MOCK_SEAT="${4:-}" PATH="$(mock_path)" sh -e -c '. "$1"; echo reached-startup' _ "$MOCK_DIR/dropin" </dev/null 2>/dev/null; }

setup_dropin
# xrdp sets XRDP_SESSION to the session's pid, not to 1 - the drop-in
# must test for the variable being set, whatever its value (found live:
# a literal-1 comparison let every remote session through).
assert_eq "drop-in, XRDP session refused: session ends before startup, message shown" "" "$(run_dropin 23440 "local desktop busy")"
assert_contains "drop-in, XRDP session refused: xmessage carries the guard's reason" "$(cat "$MOCK_CALLS")" "xmessage -center -timeout 30 refused: local desktop busy"
assert_eq "drop-in, XRDP session allowed: continues to startup" "reached-startup" "$(run_dropin 23440 "")"
assert_eq "drop-in, local login (no XRDP_SESSION): guard not even consulted" "reached-startup" "$(run_dropin "" "local desktop busy")"
# The variable alone isn't trusted: a local login (session on seat0) that
# inherited XRDP_SESSION from the systemd user environment after a remote
# logout must not be refused (seen live); a remote one (no seat) still is.
assert_eq "drop-in, leaked XRDP_SESSION in a seated local login: not refused" "reached-startup" "$(run_dropin 23440 "local desktop busy" 12 seat0)"
assert_eq "drop-in, XRDP_SESSION and a seatless session: refused" "" "$(run_dropin 23440 "local desktop busy" c10 "")"
assert_eq "drop-in, XRDP_SESSION and a seatless session (logind prints -): refused" "" "$(run_dropin 23440 "local desktop busy" c10 -)"
rm "$MOCK_BIN/ohmydebn-xrdp-session-guard"
assert_eq "drop-in, guard binary missing (package removed but drop-in left): local and remote logins unaffected" "reached-startup" "$(run_dropin 23440 "x")"
mock_cleanup

# --- firewall hint: two commands, restrictive first; silent without ufw ---
setup
OUT=$(run "$MOCK_BIN/ohmydebn-firewall-hint" 22 "SSH Server")
assert_contains "hint: restrictive rule first" "$OUT" "sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'OhMyDebn SSH Server'"
assert_contains "hint: open rule second" "$OUT" "sudo ufw allow 22/tcp comment 'OhMyDebn SSH Server'"
rm "$MOCK_BIN/ufw"
OUT=$(env -i PATH="$MOCK_BIN:/usr/bin:/bin" HOME="$H" /bin/bash "$MOCK_BIN/ohmydebn-firewall-hint" 22 "SSH Server" 2>&1)
assert_eq "hint: nothing printed when ufw isn't installed" "" "$OUT"
mock_cleanup

test_summary
