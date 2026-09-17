#!/bin/bash

# Tell the user when this update needs a reboot to finish - otherwise a
# kernel installed by finalization/updates.sh's full-upgrade sits unused
# until some unrelated reboot, with nothing ever saying why. Two signals:
#
#  - the newest installed kernel image (/boot/vmlinuz-<version>, newest
#    by version sort) isn't the one running (uname -r). Debian, Devuan,
#    Kali, Mint/LMDE and Ubuntu all name kernel images this way; Raspberry
#    Pi OS keeps its kernels under /boot/firmware instead, so with no
#    /boot/vmlinuz-* at all this signal simply stays quiet.
#  - the /run/reboot-required marker (written by Ubuntu/Mint's
#    update-notifier-common and by needrestart where installed), with the
#    package list beside it when there is one.
#
# Last finalization step on purpose: this should be the final thing on
# screen, after finale.sh's "update complete". Notice only - nothing here
# reboots anything. Under the GUI the terminal is collapsed, so a desktop
# notification carries the same message there (and the GUI itself turns
# the headline into its final status - see success_message in
# bin/ohmydebn-update-gui, which keys off REBOOT_HEADLINE's wording).
#
# The three inputs are variables (not inlined calls) so the unit test
# can point them at scratch values - tests/unit/test-reboot-notice.sh.
RUNNING_KERNEL=$(uname -r)
BOOT_DIR=/boot
REBOOT_REQUIRED_FILE=/run/reboot-required
REBOOT_HEADLINE="A reboot is needed to finish this update"

reboot_reason() {
  local newest
  newest=$(ls "$BOOT_DIR"/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -n1)
  if [ -n "$newest" ] && [ "$newest" != "$RUNNING_KERNEL" ] &&
    [ "$(printf '%s\n%s\n' "$RUNNING_KERNEL" "$newest" | sort -V | tail -n1)" = "$newest" ]; then
    echo "A newer kernel ($newest) is installed, but $RUNNING_KERNEL is still running."
  fi
  if [ -f "$REBOOT_REQUIRED_FILE" ]; then
    if [ -s "$REBOOT_REQUIRED_FILE.pkgs" ]; then
      echo "These packages asked for a reboot: $(sort -u "$REBOOT_REQUIRED_FILE.pkgs" | tr '\n' ' ')"
    else
      echo "The system has flagged that a reboot is required."
    fi
  fi
}

REBOOT_REASON=$(reboot_reason)
if [ -n "$REBOOT_REASON" ]; then
  echo
  /usr/share/ohmydebn/bin/ohmydebn-headline "$REBOOT_HEADLINE"
  echo "$REBOOT_REASON"
  echo "Reboot when it's convenient - nothing is broken until then, the new kernel just isn't in use yet."
  if [ -n "${DISPLAY:-}" ] && command -v notify-send >/dev/null 2>&1; then
    notify-send "OhMyDebn Update" "$REBOOT_HEADLINE. $REBOOT_REASON" -t 0 2>/dev/null || true
  fi
fi
