#!/bin/bash
#
# Unit tests for bin/ohmydebn-doctor, the read-only install self-check.
# Three mocked machines: a healthy systemd install (everything ok, exit
# 0), the same machine with a handful of things deliberately broken (each
# one named in the failures list, exit 1), and a healthy non-systemd
# (Devuan-style) install (timer check skipped, loginctl checked, exit 0).
# OHMYDEBN_DOCTOR_SYSROOT prefixes every system path and the external
# commands come from PATH mocks, so nothing here reads the real machine.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/ohmydebn-doctor"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== bin/ohmydebn-doctor ==="

# elf <file> <machine bytes, printf octal>: just enough of an ELF header for
# the doctor's architecture check (the machine field is at byte 18).
elf() {
  { printf '\177ELF'; head -c 14 /dev/zero; printf "$2"; } >"$1"
}

# build_machine <systemd: yes|no>: a scratch SYSROOT + HOME describing a healthy install.
build_machine() {
  local systemd="$1"
  mock_init
  ROOT="$MOCK_DIR/root"
  H="$MOCK_DIR/home"
  OMD="$ROOT/usr/share/ohmydebn"
  mkdir -p "$OMD/bin" "$OMD/install/packaging" "$OMD/install/keybinding" "$OMD/config/ohmydebn-skill" \
    "$ROOT/etc/apt/sources.list.d" "$ROOT/usr/share/keyrings" "$ROOT/etc/X11" "$ROOT/etc/lightdm/lightdm.conf.d" \
    "$ROOT/usr/share/cinnamon/extensions/gTile@OhMyDebn" "$ROOT/usr/share/ohmydebn-themes/hackerman" \
    "$H/.local/state/ohmydebn-config" "$H/.config/ohmydebn/current/theme" "$H/.config/ohmydebn/themes" \
    "$H/.config/cinnamon/spices/gTile@OhMyDebn" "$H/.claude/skills" "$H/.gemini/antigravity/global_skills" "$H/.agents/skills" \
    "$H/.local/share/omarchy" "$H/.local/state/omarchy" "$H/.config/ohmydebn/backgrounds"
  [ "$systemd" = yes ] && mkdir -p "$ROOT/run/systemd/system"
  printf 'PRETTY_NAME="Debian GNU/Linux 13 (trixie)"\nID=debian\nVERSION_CODENAME=trixie\n' >"$ROOT/etc/os-release"
  echo "4.8.0" >"$OMD/VERSION"
  printf 'PACKAGES=(\n  alacritty\n  bat # comment\n  cinnamon-desktop-environment\n)\n' >"$OMD/install/packaging/dependencies.sh"
  printf 'keybinding-custom 0 "Browser" "/usr/share/ohmydebn/bin/ohmydebn-browser-tiled" "['"'"'<Super>B'"'"']" "Press Super + B"\nkeybinding-custom 1 "Update" "/usr/share/ohmydebn/bin/ohmydebn-update-gui" "['"'"'<Ctrl><Super>U'"'"']" "Press Ctrl+Super+U"\n' >"$OMD/install/keybinding/keybinding-custom.txt"
  for w in ohmydebn-ai ohmydebn-ai-cli ohmydebn-opencode-cli ohmydebn-claude-code-cli ohmydebn-codex-cli ohmydebn-grok-cli ohmydebn-omp-cli ohmydebn-pi-cli ohmydebn-power omarchy; do
    printf '#!/bin/bash\n' >"$OMD/bin/$w"; chmod +x "$OMD/bin/$w"
  done
  : >"$ROOT/etc/apt/sources.list.d/ohmydebn.sources"; echo key >"$ROOT/usr/share/keyrings/ohmydebn-keyring.gpg"
  echo "/usr/sbin/lightdm" >"$ROOT/etc/X11/default-display-manager"
  : >"$ROOT/etc/lightdm/lightdm.conf.d/50-ohmydebn-session.conf"
  : >"$ROOT/usr/share/cinnamon/extensions/gTile@OhMyDebn/metadata.json"
  : >"$H/.local/state/ohmydebn"; : >"$H/.local/state/ohmydebn-config/zshrc-20260116"
  echo hackerman >"$H/.config/ohmydebn/current/theme.name"
  printf 'accent = "#11aa22"\nbackground = "#000000"\n' >"$H/.config/ohmydebn/current/theme/colors.toml"
  printf 'bg0=#000000F2\nbg1=#000000\nbg3=#11aa22F2\nfg0=#ffffff\n' >"$H/.config/ohmydebn/current/picker-colors"
  : >"$H/.config/ohmydebn/backgrounds/wall.jpg"; ln -s "$H/.config/ohmydebn/backgrounds/wall.jpg" "$H/.config/ohmydebn/current/background"
  echo opencode >"$H/.config/ohmydebn/current/default-ai"
  printf '{"autoclose": {"type": "checkbox", "default": true, "value": true}}\n' >"$H/.config/cinnamon/spices/gTile@OhMyDebn/gTile@OhMyDebn.json"
  for d in .claude/skills .gemini/antigravity/global_skills .agents/skills; do ln -s /usr/share/ohmydebn/config/ohmydebn-skill "$H/$d/ohmydebn"; done
  printf "alias c='x'\nalias pi='x'\nalias codex='x'\nalias grok='x'\nalias omp='x'\nalias claude='x'\nalias a='x'\n" >"$H/.zshrc"
  ln -s "$H/.config/ohmydebn" "$H/.config/omarchy"
  ln -s /usr/share/ohmydebn-themes "$H/.local/share/omarchy/themes"
  ln -s "$H/.config/ohmydebn/current" "$H/.local/state/omarchy/current"

  # System: a finished update, a third-party repo with its pin, the
  # firewall on, a VM with SPICE, UEFI with fwupd's signed binary, and the
  # running kernel the newest one installed.
  mkdir -p "$H/.local/state/ohmydebn-logs" "$ROOT/etc/apt/preferences.d" "$ROOT/etc/ufw" "$ROOT/dev/virtio-ports" \
    "$ROOT/sys/firmware/efi" "$ROOT/usr/lib/fwupd/efi" "$ROOT/boot"
  printf 'Checking for an updated ohmydebn package\nOhMyDebn update complete - version: 4.8.0\n' >"$H/.local/state/ohmydebn-logs/update-1.log"
  ln -s "$H/.local/state/ohmydebn-logs/update-1.log" "$H/.local/state/ohmydebn-logs/update-latest.log"
  : >"$ROOT/etc/apt/sources.list.d/tailscale.list"; : >"$ROOT/etc/apt/preferences.d/tailscale.pref"
  echo "ENABLED=yes" >"$ROOT/etc/ufw/ufw.conf"
  : >"$ROOT/dev/virtio-ports/com.redhat.spice.0"
  : >"$ROOT/usr/lib/fwupd/efi/fwupdx64.efi.signed"
  : >"$ROOT/boot/vmlinuz-6.12.1-amd64"

  # Neovim: the plugin package (two plugins, a parser, a Mason tool) and this
  # user's copy of it, with the current theme's colorscheme plugin (named
  # "pixel" by its spec, as OhMyDebn's default theme does it).
  local seed="$ROOT/usr/lib/ohmydebn-neovim-plugins" data="$H/.local/share/nvim"
  mkdir -p "$seed/config" "$seed/data/site/parser" "$seed/data/mason/packages/stylua" \
    "$data/lazy/LazyVim" "$data/lazy/blink.cmp/target/release" "$data/lazy/pixel" "$data/site/parser" "$data/mason/packages/stylua"
  echo '{ "LazyVim": { "commit": "a" }, "blink.cmp": { "commit": "b" }, "pixel": { "commit": "c" } }' >"$seed/config/lazy-lock.json"
  elf "$seed/data/site/parser/lua.so" '\076\000'
  elf "$data/site/parser/lua.so" '\076\000'
  elf "$data/lazy/blink.cmp/target/release/libblink_cmp_fuzzy.so" '\076\000'
  sha256sum "$seed/config/lazy-lock.json" | cut -d' ' -f1 >"$H/.local/state/ohmydebn-config/nvim-plugins-seeded"
  printf 'return {\n  { "bjarneo/pixel.nvim", name = "pixel" },\n  { "LazyVim/LazyVim", opts = { colorscheme = "pixel" } },\n}\n' \
    >"$H/.config/ohmydebn/current/theme/neovim.lua"

  # External commands. dpkg knows the packages a healthy machine has.
  mock_bin dpkg <<'EOF2'
#!/bin/bash
case "$*" in
"-s ohmydebn"|"-s ohmydebn-gtile"|"-s ohmydebn-themes"|"-s alacritty"|"-s bat"|"-s cinnamon-desktop-environment") exit 0 ;;
"-s ohmydebn-neovim-plugins"|"-s ufw"|"-s fwupd") exit 0 ;;
"--print-architecture") echo amd64; exit 0 ;;
"--audit") [ -n "${MOCK_DPKG_AUDIT:-}" ] && echo "$MOCK_DPKG_AUDIT"; exit 0 ;;
esac
exit 1
EOF2
  mock_bin dpkg-query <<'EOF2'
#!/bin/bash
case "$*" in
*ohmydebn-neovim) echo "0.12.5" ;;
*) echo "4.8.0" ;;
esac
EOF2
  mock_bin apt-mark <<'EOF2'
#!/bin/bash
[ "$1" = showhold ] && [ -n "${MOCK_HELD:-}" ] && echo "$MOCK_HELD"
exit 0
EOF2
  mock_bin df <<'EOF2'
#!/bin/bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/vda1 80000000 20000000 %s 25%% /\n' "${MOCK_FREE_KB:-50000000}"
EOF2
  mock_bin uname <<'EOF2'
#!/bin/bash
echo "6.12.1-amd64"
EOF2
  mock_bin pgrep <<'EOF2'
#!/bin/bash
exit "${MOCK_PGREP_EXIT:-0}"
EOF2
  mock_bin nvim <<'EOF2'
#!/bin/bash
[ "$1" = "--version" ] && printf 'NVIM v%s\nBuild type: Release\n' "${MOCK_NVIM_VERSION:-0.12.5}"
EOF2
  mock_bin apt-cache <<'EOF2'
#!/bin/bash
printf 'ohmydebn:\n  Installed: 4.8.0\n  Candidate: 4.8.0\n'
EOF2
  mock_bin update-alternatives <<'EOF2'
#!/bin/bash
echo "Value: ${MOCK_XSM:-/usr/bin/cinnamon-session}"
EOF2
  mock_bin systemctl <<'EOF2'
#!/bin/bash
exit "${MOCK_TIMER_EXIT:-0}"
EOF2
  mock_bin gsettings <<'EOF2'
#!/bin/bash
case "$*" in
"list-schemas") exit 0 ;;
"get org.cinnamon enabled-extensions") echo "['gTile@OhMyDebn']" ;;
"get org.cinnamon.desktop.keybindings custom-list") echo "['custom-0', 'custom-1'${MOCK_EXTRA_LIST:-}]" ;;
*custom-0/\ command) echo "'/usr/share/ohmydebn/bin/ohmydebn-browser-tiled'" ;;
*custom-1/\ command) echo "'${MOCK_CUSTOM1:-/usr/share/ohmydebn/bin/ohmydebn-update-gui}'" ;;
*) echo "''" ;;
esac
EOF2
  mock_bin python3 <<'EOF2'
#!/bin/bash
exit 0
EOF2
  for t in toilet ttfx alacritty gdbus notify-send script flock loginctl; do
    mock_bin "$t" <<'EOF2'
#!/bin/bash
exit 0
EOF2
  done
}

run_doctor() {
  # Mocks first, then the real coreutils the doctor itself needs (sed,
  # grep, readlink, date, ...) - env -i keeps the real desktop's variables
  # (DBUS, XDG_*) from leaking into the mocked machine.
  OUTPUT=$(env -i HOME="$H" PATH="$MOCK_BIN:/usr/bin:/bin" XDG_CURRENT_DESKTOP=X-Cinnamon DISPLAY=:0 \
    OHMYDEBN_DOCTOR_SYSROOT="$ROOT" "$@" /bin/bash "$SCRIPT" 2>&1)
  EXIT_CODE=$?
}

# --- healthy systemd install: everything ok ---
build_machine yes
run_doctor
assert_eq "healthy: exits 0" "0" "$EXIT_CODE"
assert_not_contains "healthy: no FAIL lines" "$OUTPUT" "FAIL -"
assert_contains "healthy: supported distro" "$OUTPUT" "ok - supported distro"
assert_contains "healthy: dependencies all installed" "$OUTPUT" "ok - every package in dependencies.sh is installed"
assert_contains "healthy: timer enabled under systemd" "$OUTPUT" "ok - update-check user timer enabled"
assert_contains "healthy: keybindings verified" "$OUTPUT" "ok - every custom keybinding runs the command keybinding-custom.txt says"
assert_contains "healthy: gTile booleans clean" "$OUTPUT" "ok - gTile checkbox settings are real booleans"
assert_contains "healthy: summary counts no failures" "$OUTPUT" " 0 failed"
assert_contains "healthy: nvim is the package's" "$OUTPUT" "ok - nvim on PATH is ohmydebn-neovim's (0.12.5)"
assert_contains "healthy: tested plugin set installed" "$OUTPUT" "ok - the tested plugin set is installed for this user"
assert_contains "healthy: every plugin present" "$OUTPUT" "ok - every plugin in the tested set is present"
assert_contains "healthy: parsers present" "$OUTPUT" "ok - every treesitter parser in the set is present"
assert_contains "healthy: Mason tools present" "$OUTPUT" "ok - every Mason tool in the set is present"
assert_contains "healthy: theme's plugin found by its spec's name" "$OUTPUT" "ok - the current theme's Neovim plugins are installed"
assert_contains "healthy: blink.cmp's matcher is this machine's" "$OUTPUT" "ok - ~/.local/share/nvim/lazy/blink.cmp/target/release/libblink_cmp_fuzzy.so is built for this machine"
assert_contains "healthy: the lua parser is this machine's" "$OUTPUT" "ok - ~/.local/share/nvim/site/parser/lua.so is built for this machine"
assert_contains "healthy: latest update completed" "$OUTPUT" "ok - the latest update completed"
assert_contains "healthy: third-party repo pinned" "$OUTPUT" "ok - third-party apt repos pinned to their own packages (1)"
assert_contains "healthy: dpkg clean" "$OUTPUT" "ok - no half-installed packages (dpkg --audit)"
assert_contains "healthy: disk space" "$OUTPUT" "ok - at least 2 GB free on / (47 GB)"
assert_contains "healthy: home disk space" "$OUTPUT" "ok - at least 2 GB free on home directory"
assert_not_contains "healthy: no reboot needed" "$OUTPUT" "reboot needed"
assert_not_contains "healthy: nothing held" "$OUTPUT" "held packages"
assert_contains "healthy: firewall on" "$OUTPUT" "ok - firewall (ufw) enabled"
assert_contains "healthy: SPICE agent running" "$OUTPUT" "ok - VM display: spice-vdagentd running"
assert_contains "healthy: fwupd signed binary" "$OUTPUT" "ok - firmware updates: fwupd's signed EFI binary installed"
assert_not_contains "healthy: Debian machine skips the Ubuntu sources check" "$OUTPUT" "Ubuntu-based"
assert_contains "healthy: no DCONF_PROFILE" "$OUTPUT" "ok - DCONF_PROFILE not set in the session"
mock_cleanup

# --- system problems: each one caught and explained ---
build_machine yes
printf 'Checking for an updated ohmydebn package\nCould not refresh the OhMyDebn package repository - update stopped\n' >"$H/.local/state/ohmydebn-logs/update-1.log"
: >"$ROOT/etc/apt/sources.list.d/claude-code.list"                                 # a repo without its pin
echo "ENABLED=no" >"$ROOT/etc/ufw/ufw.conf"
rm "$ROOT/usr/lib/fwupd/efi/fwupdx64.efi.signed"
: >"$ROOT/boot/vmlinuz-6.12.9-amd64"                                               # newer kernel installed
run_doctor "MOCK_DPKG_AUDIT=The following packages are only half configured" MOCK_FREE_KB=900000 MOCK_HELD=linux-image-amd64 MOCK_PGREP_EXIT=1 DCONF_PROFILE=cosmic
assert_eq "system problems: exits 1" "1" "$EXIT_CODE"
assert_contains "system problems: stopped update names why" "$OUTPUT" "FAIL - the latest update completed (Could not refresh the OhMyDebn package repository - update stopped)"
assert_contains "system problems: unpinned repo named" "$OUTPUT" "FAIL - third-party apt repos pinned to their own packages (no pin for: claude-code)"
assert_contains "system problems: dpkg says how to fix" "$OUTPUT" "FAIL - no half-installed packages (dpkg --audit) (run: sudo dpkg --configure -a)"
assert_contains "system problems: low disk named" "$OUTPUT" "FAIL - at least 2 GB free on / (878 MB free)"
assert_contains "system problems: held package listed" "$OUTPUT" "held packages (not updated): linux-image-amd64"
assert_contains "system problems: reboot for the new kernel" "$OUTPUT" "reboot needed: kernel 6.12.9-amd64 is installed, 6.12.1-amd64 is running"
assert_contains "system problems: firewall off" "$OUTPUT" "FAIL - firewall (ufw) enabled (run: sudo ufw enable)"
assert_contains "system problems: SPICE agent not running" "$OUTPUT" "FAIL - VM display: spice-vdagentd running"
assert_contains "system problems: fwupd-signed missing" "$OUTPUT" "FAIL - firmware updates: fwupd's signed EFI binary installed (run: sudo apt install fwupd-signed)"
assert_contains "system problems: DCONF_PROFILE caught" "$OUTPUT" "FAIL - DCONF_PROFILE not set in the session (DCONF_PROFILE=cosmic)"
mock_cleanup

# --- an update that never finished, and one that's still running ---
build_machine yes
printf 'Checking for an updated ohmydebn package\nInstalling packages\n' >"$H/.local/state/ohmydebn-logs/update-1.log"
run_doctor
assert_contains "unfinished update: reported" "$OUTPUT" "FAIL - the latest update completed (it didn't finish"
sleep 60 &
mkdir -p "$MOCK_DIR/run"; echo "$!" >"$MOCK_DIR/run/ohmydebn-update-$(id -u).lock"
run_doctor XDG_RUNTIME_DIR="$MOCK_DIR/run"
assert_contains "running update: skipped, not failed" "$OUTPUT" "skip - the latest update completed (an update is running now)"
kill %1 2>/dev/null
mock_cleanup

# --- an Ubuntu-based distro with Debian's sources mixed in ---
build_machine yes
printf 'PRETTY_NAME="Zorin OS 18"\nID=zorin\nID_LIKE="ubuntu debian"\nVERSION_CODENAME=noble\nUBUNTU_CODENAME=noble\n' >"$ROOT/etc/os-release"
echo "URIs: https://deb.debian.org/debian" >"$ROOT/etc/apt/sources.list.d/debian.sources"
run_doctor
assert_contains "Ubuntu-based with Debian sources: caught" "$OUTPUT" "FAIL - Ubuntu-based: no Debian apt sources mixed in (deb.debian.org found in /etc/apt)"
rm "$ROOT/etc/apt/sources.list.d/debian.sources"
run_doctor
assert_contains "Ubuntu-based with its own sources: ok" "$OUTPUT" "ok - Ubuntu-based: no Debian apt sources mixed in"
mock_cleanup

# --- Neovim, broken in each of the ways the doctor checks ---
build_machine yes
N="$H/.local/share/nvim"
echo stale >"$H/.local/state/ohmydebn-config/nvim-plugins-seeded"                 # refresh never finished
rm -r "$N/lazy/LazyVim"                                                            # a plugin missing
rm "$N/site/parser/lua.so"                                                         # a parser missing
rm -r "$N/mason/packages/stylua"                                                   # a Mason tool missing
printf 'return { { "bjarneo/hackerman.nvim", dependencies = { "bjarneo/aether.nvim" } } }\n' >"$H/.config/ohmydebn/current/theme/neovim.lua"
elf "$N/lazy/blink.cmp/target/release/libblink_cmp_fuzzy.so" '\267\000'         # arm64 build on amd64
run_doctor MOCK_NVIM_VERSION=0.10.4                                                # the distro's nvim shadows it
assert_eq "broken neovim: exits 1" "1" "$EXIT_CODE"
assert_contains "broken neovim: shadowing nvim named" "$OUTPUT" "FAIL - nvim on PATH is ohmydebn-neovim's (nvim reports 0.10.4, package is 0.12.5"
assert_contains "broken neovim: unfinished refresh says how to fix" "$OUTPUT" "FAIL - the tested plugin set is installed for this user (run: ohmydebn-update)"
assert_contains "broken neovim: missing plugin named" "$OUTPUT" "FAIL - every plugin in the tested set is present (missing: LazyVim)"
assert_contains "broken neovim: missing parser named" "$OUTPUT" "FAIL - every treesitter parser in the set is present (missing: lua)"
assert_contains "broken neovim: missing Mason tool named" "$OUTPUT" "FAIL - every Mason tool in the set is present (missing: stylua)"
assert_contains "broken neovim: theme plugin and its dependency named" "$OUTPUT" "FAIL - the current theme's Neovim plugins are installed (missing: bjarneo/aether.nvim bjarneo/hackerman.nvim)"
assert_contains "broken neovim: wrong-architecture matcher caught" "$OUTPUT" "FAIL - ~/.local/share/nvim/lazy/blink.cmp/target/release/libblink_cmp_fuzzy.so is built for this machine (wrong architecture)"
assert_contains "broken neovim: missing parser file caught" "$OUTPUT" "FAIL - ~/.local/share/nvim/site/parser/lua.so is built for this machine (missing)"
mock_cleanup

# --- no plugin package (a non-standard install): Neovim checks skipped ---
build_machine yes
sed -i 's/^"-s ohmydebn-neovim-plugins"|//' "$MOCK_BIN/dpkg"
run_doctor
assert_contains "no plugin package: Neovim checks skipped" "$OUTPUT" "skip - Neovim checks (ohmydebn-neovim-plugins not installed)"
assert_eq "no plugin package: still exits 0" "0" "$EXIT_CODE"
mock_cleanup

# --- the same machine, broken in several specific ways ---
build_machine yes
rm "$H/.agents/skills/ohmydebn"                                                    # one skill link gone
printf '{"useMonitorCenter": {"type": "checkbox", "default": "false", "value": "false"}}\n' >"$H/.config/cinnamon/spices/gTile@OhMyDebn/gTile@OhMyDebn.json"
rm "$H/.config/ohmydebn/backgrounds/wall.jpg"                                      # dangling background link
echo "3.9.0" >"$OMD/VERSION"                                                       # package/tree version mismatch
sed -i 's/  bat # comment/  bat # comment\n  gir1.2-wnck-3.0/' "$OMD/install/packaging/dependencies.sh"  # a dependency dpkg doesn't know
run_doctor MOCK_CUSTOM1=/usr/bin/something-else
assert_eq "broken: exits 1" "1" "$EXIT_CODE"
assert_contains "broken: missing skill link named" "$OUTPUT" "FAIL - skill link ~/.agents/skills/ohmydebn"
assert_contains "broken: other skill links still ok" "$OUTPUT" "ok - skill link ~/.claude/skills/ohmydebn"
assert_contains "broken: string booleans in gTile settings caught" "$OUTPUT" "FAIL - gTile checkbox settings are real booleans"
assert_contains "broken: dangling background caught" "$OUTPUT" "FAIL - current background symlink resolves to a file"
assert_contains "broken: version mismatch caught with both values" "$OUTPUT" "FAIL - package version matches VERSION file (dpkg 4.8.0 vs file 3.9.0)"
assert_contains "broken: missing dependency named" "$OUTPUT" "missing: gir1.2-wnck-3.0"
assert_contains "broken: wrong keybinding command named" "$OUTPUT" "differs: custom-1"
assert_contains "broken: summary lists failures" "$OUTPUT" "  failed:"
mock_cleanup

# --- the user's own keybindings.txt: a retargeted stock slot is not a failure ---
build_machine yes
echo 'keybinding "Update" "/usr/bin/something-else" "['"'"'<Super>U'"'"']"' >"$H/.config/ohmydebn/keybindings.txt"
printf 'custom 1\nuser 1000\n' >"$H/.local/state/ohmydebn-config/keybindings-user-touched"
sha256sum <"$H/.config/ohmydebn/keybindings.txt" | cut -d' ' -f1 >"$H/.local/state/ohmydebn-config/keybindings-user-sha256"
run_doctor MOCK_CUSTOM1=/usr/bin/something-else "MOCK_EXTRA_LIST=, 'custom-1000'"
assert_eq "user keybindings: exits 0" "0" "$EXIT_CODE"
assert_contains "user keybindings: retargeted stock slot exempted" "$OUTPUT" "ok - every custom keybinding runs the command keybinding-custom.txt says"
assert_contains "user keybindings: file parses" "$OUTPUT" "ok - keybindings.txt parses"
assert_contains "user keybindings: applied" "$OUTPUT" "ok - keybindings.txt applied"
assert_contains "user keybindings: user slot listed" "$OUTPUT" "ok - user keybinding slots in custom-list (1)"
echo '# edited since' >>"$H/.config/ohmydebn/keybindings.txt"
run_doctor MOCK_CUSTOM1=/usr/bin/something-else
assert_eq "user keybindings edited: exits 1" "1" "$EXIT_CODE"
assert_contains "user keybindings edited: says how to fix" "$OUTPUT" "FAIL - keybindings.txt applied (edited but not applied - run ohmydebn-keybindings-apply)"
assert_contains "user keybindings edited: missing user slot named" "$OUTPUT" "FAIL - user keybinding slots in custom-list (missing: custom-1000)"
mock_cleanup

# --- healthy non-systemd (Devuan-style) install with SLiM ---
build_machine no
echo "/usr/bin/slim" >"$ROOT/etc/X11/default-display-manager"
run_doctor
assert_eq "no systemd: exits 0" "0" "$EXIT_CODE"
assert_contains "no systemd: timer check skipped, not failed" "$OUTPUT" "skip - update-check user timer"
assert_contains "no systemd: loginctl checked instead" "$OUTPUT" "ok - elogind's loginctl present for the power menu"
assert_contains "no systemd: SLiM session alternative checked" "$OUTPUT" "ok - SLiM: x-session-manager alternative is cinnamon-session"
assert_not_contains "no systemd: no FAIL lines" "$OUTPUT" "FAIL -"
mock_cleanup

# --- SLiM with the alternative still on XFCE: the default-session bug shape ---
build_machine no
echo "/usr/bin/slim" >"$ROOT/etc/X11/default-display-manager"
run_doctor MOCK_XSM=/usr/bin/startxfce4
assert_eq "SLiM on XFCE: exits 1" "1" "$EXIT_CODE"
assert_contains "SLiM on XFCE: names the wrong alternative" "$OUTPUT" "FAIL - SLiM: x-session-manager alternative is cinnamon-session (is: /usr/bin/startxfce4)"
mock_cleanup

# --- no session bus (run over ssh): gsettings-backed checks skip rather than fail ---
build_machine yes
mock_bin gsettings <<'EOF2'
#!/bin/bash
exit 1
EOF2
run_doctor
assert_contains "no bus: extension check skipped" "$OUTPUT" "skip - gTile@OhMyDebn enabled in Cinnamon (no session bus"
assert_contains "no bus: keybinding check skipped" "$OUTPUT" "skip - custom keybindings match keybinding-custom.txt"
assert_eq "no bus: still exits 0 when nothing else is wrong" "0" "$EXIT_CODE"
mock_cleanup


# --- the menu's window wrapper: a titled terminal running the pause script, which runs the doctor then waits ---
mock_init
mock_bin ohmydebn-terminal <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-terminal $*"
EOF2
mock_bin ohmydebn-doctor <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-doctor"
exit 1
EOF2
mock_bin ohmydebn-headline <<'EOF2'
#!/bin/bash
mock_log "ohmydebn-headline $*"
EOF2
for s_ in ohmydebn-doctor-gui ohmydebn-doctor-pause; do
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g" "$REPO_ROOT/bin/$s_" >"$MOCK_BIN/$s_"; chmod +x "$MOCK_BIN/$s_"
done
PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-doctor-gui" >/dev/null 2>&1
assert_contains "doctor-gui: opens a terminal titled for the tile rule" "$(cat "$MOCK_CALLS")" "ohmydebn-terminal --title OhMyDebn Doctor -e $MOCK_BIN/ohmydebn-doctor-pause"
: >"$MOCK_CALLS"
PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-doctor-pause" </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "doctor-pause: runs the doctor" "$CALLS" "ohmydebn-doctor"
assert_contains "doctor-pause: keeps the window open afterwards even when the doctor reports failures" "$CALLS" "ohmydebn-headline Press Enter to close this window"
mock_cleanup

test_summary
