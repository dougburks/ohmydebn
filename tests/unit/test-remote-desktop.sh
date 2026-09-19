#!/bin/bash
#
# Unit tests for the Remote Desktop (XRDP) scripts: ohmydebn-remote-desktop
# (menu launcher), -install, -remove, ohmydebn-xrdp-session-guard (the PAM
# hook) and ohmydebn-firewall-hint. The PAM file, systemd signal directory
# and ~/.xsession are sed-patched/HOME'd into a scratch root; sudo runs its
# command for real against those paths except apt/systemctl/service/adduser,
# which are only logged; dpkg answers from MOCK_INSTALLED; loginctl answers
# from a session table the guard tests write.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-remote-desktop / -install / -remove / ohmydebn-xrdp-session-guard / ohmydebn-firewall-hint ==="

setup() {
  mock_init
  ROOT="$MOCK_DIR/root"; H="$MOCK_DIR/home"
  mkdir -p "$ROOT/etc/pam.d" "$H"
  printf '#%%PAM-1.0\n@include common-auth\n@include common-account\n@include common-session\n' >"$ROOT/etc/pam.d/xrdp-sesman"
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
  for script in ohmydebn-remote-desktop ohmydebn-remote-desktop-install ohmydebn-remote-desktop-remove ohmydebn-xrdp-session-guard ohmydebn-firewall-hint; do
    sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#^PAM_FILE=.*#PAM_FILE=$ROOT/etc/pam.d/xrdp-sesman#; s#^SYSTEMD_DIR=.*#SYSTEMD_DIR=$ROOT/run/systemd/system#" \
      "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
    chmod +x "$MOCK_BIN/$script"
  done
  PAM="$ROOT/etc/pam.d/xrdp-sesman"
}
run() { HOME="$H" PATH="$(mock_path)" MOCK_INSTALLED="${MOCK_INSTALLED:-}" MOCK_XRDP_GROUPS="${MOCK_XRDP_GROUPS:-xrdp}" bash "$@" </dev/null 2>&1; }

# --- install, fresh, systemd: packages, TLS group, PAM guard, ~/.xsession, service, no firewall rule ---
setup
OUT=$(MOCK_INSTALLED="" run "$MOCK_BIN/ohmydebn-remote-desktop-install" --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_contains "fresh: installs xrdp and xorgxrdp" "$CALLS" "sudo /usr/bin/apt -y install xrdp xorgxrdp"
assert_contains "fresh: xrdp user added to ssl-cert for the TLS key" "$CALLS" "sudo adduser xrdp ssl-cert"
assert_eq "fresh: PAM guard inserted right after common-account" "@include common-account
account  requisite pam_exec.so quiet $MOCK_BIN/ohmydebn-xrdp-session-guard" "$(sed -n '/common-account/,+1p' "$PAM")"
assert_eq "fresh: ~/.xsession written with OhMyDebn's marker" "yes" "$(grep -Fq '# OhMyDebn Cinnamon session for XRDP' "$H/.xsession" && echo yes || echo no)"
assert_eq "fresh: ~/.xsession is executable POSIX sh" "yes" "$([ -x "$H/.xsession" ] && sh -n "$H/.xsession" && echo yes || echo no)"
assert_contains "fresh: service enabled under systemd" "$CALLS" "sudo systemctl enable --now xrdp"
assert_not_contains "fresh: no firewall rule added" "$CALLS" "ufw allow"
assert_contains "fresh: firewall guidance printed for 3389" "$OUT" "sudo ufw allow from 192.168.1.0/24 to any port 3389 proto tcp comment 'OhMyDebn Remote Desktop'"
assert_contains "fresh: address shown" "$OUT" "192.0.2.10:3389"
mock_cleanup

# --- install again, everything already in place: idempotent ---
setup
run "$MOCK_BIN/ohmydebn-remote-desktop-install" --skip-prompt >/dev/null
cp "$H/.xsession" "$MOCK_DIR/xsession-first"
: >"$MOCK_CALLS"
OUT=$(MOCK_INSTALLED="xrdp" MOCK_XRDP_GROUPS="xrdp ssl-cert" run "$MOCK_BIN/ohmydebn-remote-desktop-install" --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "rerun: no apt" "$CALLS" "apt"
assert_not_contains "rerun: adduser skipped when already a member" "$CALLS" "adduser"
assert_eq "rerun: PAM guard line present exactly once" "1" "$(grep -c ohmydebn-xrdp-session-guard "$PAM")"
assert_eq "rerun: our ~/.xsession rewritten identically" "yes" "$(cmp -s "$H/.xsession" "$MOCK_DIR/xsession-first" && echo yes || echo no)"
mock_cleanup

# --- install with the user's own ~/.xsession: left alone ---
setup
printf '#!/bin/sh\nexec startxfce4\n' >"$H/.xsession"
OUT=$(MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-install" --skip-prompt)
assert_eq "own xsession: file untouched" "#!/bin/sh
exec startxfce4" "$(cat "$H/.xsession")"
assert_contains "own xsession: user told it's being left alone" "$OUT" "Leaving your existing ~/.xsession alone"
mock_cleanup

# --- install without systemd (Devuan/LCOS): service, not systemctl ---
MOCK_SYSTEMD=false setup
OUT=$(MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-install" --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_not_contains "no systemd: systemctl never called" "$CALLS" "systemctl"
assert_contains "no systemd: service restart used" "$CALLS" "sudo service xrdp restart"
mock_cleanup

# --- install, prompt cancelled (EOF): nothing happens ---
setup
run "$MOCK_BIN/ohmydebn-remote-desktop-install" >/dev/null
EXIT_CODE=$?
assert_eq "cancelled at the prompt: exits non-zero" "1" "$EXIT_CODE"
assert_eq "cancelled at the prompt: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- menu launcher: not installed -> presentation with the installer; installed -> status window ---
setup
MOCK_INSTALLED="" run "$MOCK_BIN/ohmydebn-remote-desktop" >/dev/null
assert_contains "launcher, not installed: install presented" "$(cat "$MOCK_CALLS")" "ohmydebn-launch-floating-terminal-with-presentation Remote Desktop $MOCK_BIN/ohmydebn-remote-desktop-install"
mock_cleanup
setup
MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop" >/dev/null
CALLS=$(cat "$MOCK_CALLS")
assert_contains "launcher, installed: status window with the address" "$CALLS" "192.0.2.10:3389"
assert_contains "launcher, installed: status command branches on systemd" "$CALLS" "if [ -d /run/systemd/system ]; then systemctl is-active xrdp; else service xrdp status; fi"
assert_contains "launcher, installed: firewall hint included" "$CALLS" "ohmydebn-firewall-hint 3389 'Remote Desktop'"
mock_cleanup

# --- remove: PAM line out, our ~/.xsession gone, service stopped, purged; firewall left alone ---
setup
run "$MOCK_BIN/ohmydebn-remote-desktop-install" --skip-prompt >/dev/null
: >"$MOCK_CALLS"
OUT=$(MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-remove" --skip-prompt)
CALLS=$(cat "$MOCK_CALLS")
assert_eq "remove: PAM file back to the package's content" "#%PAM-1.0
@include common-auth
@include common-account
@include common-session" "$(cat "$PAM")"
assert_eq "remove: our ~/.xsession removed" "no" "$([ -e "$H/.xsession" ] && echo yes || echo no)"
assert_contains "remove: service disabled" "$CALLS" "sudo systemctl disable --now xrdp xrdp-sesman"
assert_contains "remove: packages purged" "$CALLS" "sudo /usr/bin/apt -y purge xrdp xorgxrdp"
assert_not_contains "remove: no ufw change" "$CALLS" "ufw delete"
assert_contains "remove: user told how to drop their own rule" "$OUT" "sudo ufw delete"
mock_cleanup

# --- remove with the user's own ~/.xsession: kept ---
setup
printf '#!/bin/sh\nexec startxfce4\n' >"$H/.xsession"
MOCK_INSTALLED="xrdp" run "$MOCK_BIN/ohmydebn-remote-desktop-remove" --skip-prompt >/dev/null
assert_eq "remove, own xsession: kept" "yes" "$([ -f "$H/.xsession" ] && echo yes || echo no)"
mock_cleanup

# --- remove when not installed: says so, does nothing ---
setup
OUT=$(MOCK_INSTALLED="" run "$MOCK_BIN/ohmydebn-remote-desktop-remove" --skip-prompt)
assert_contains "remove, not installed: message" "$OUT" "not currently installed"
assert_eq "remove, not installed: nothing run" "" "$(cat "$MOCK_CALLS")"
mock_cleanup

# --- the PAM guard: loginctl answers from a table the test writes ---
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
run_guard() { PAM_USER="$1" PATH="$(mock_path)" MOCK_SESSION_TABLE="$MOCK_SESSION_TABLE" OHMYDEBN_XRDP_ALLOW_SHARED_USER="${2:-}" bash "$MOCK_BIN/ohmydebn-xrdp-session-guard" </dev/null >/dev/null 2>&1; echo $?; }

setup_guard
printf '2 1000 alice seat0 tty7\n' >"$MOCK_SESSION_TABLE"; session 2 seat0 user active x11
assert_eq "guard: user with a local x11 seat session is rejected" "1" "$(run_guard alice)"
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
assert_eq "guard: no PAM_USER -> allowed (nothing to check)" "0" "$(PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-xrdp-session-guard" </dev/null >/dev/null 2>&1; echo $?)"
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
