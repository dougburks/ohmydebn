# TODO

Work deferred during 4.16.0 testing, for the next release. Each item says what's wrong, where, and the likely fix; check the code before relying on line numbers.

## Firewall hint: suggest the machine's own subnet

`bin/ohmydebn-firewall-hint` always uses 192.168.1.0/24 as its "allow from one range" example. Suggest the machine's own subnet instead (from the default route's interface), and fall back to the example when there isn't one. Found when the Debian 13 VM (192.168.199.20) got a rule that wouldn't admit its host.

## Fresh installs say "this update"

On a fresh install, two headlines still say "this update":

- "Cinnamon will restart at the end of this update for gTile" (`install/finalization/gtile-restart-flag.sh`)
- "A reboot is needed to finish this update" (`install/finalization/reboot-notice.sh`)

The wording has been there since September. `bin/ohmydebn-update-gui` keeps its own copy of `REBOOT_HEADLINE` and keys its final status off that wording, so change both together.

## Super+K: a fast local hotkey list

Super+K (slot 4 in `install/keybinding/keybinding-custom.txt`) opens https://ohmydebn.org/hotkeys/ in a browser web app. That's slow, needs the network, and shows the documented stock hotkeys rather than the user's own. Replace it with a fast local viewer like Omarchy's: read the live bindings (Cinnamon's custom list plus the stock ones) and show them in a searchable list, probably with `ohmydebn-menu-picker`.

Changing slot 4's command on existing installs needs a targeted fix like `rename_stock_keybinding`, not a `KEYBINDING_STATE` bump (see AGENTS.md). Update `hotkeys.md` and the release notes in `ohmydebn-docs`.

## needrestart could stall updates (unconfirmed)

Debian's `docker.io` Recommends `needrestart`, so installing Docker on Debian brings it in. By default it's interactive: after an apt run that upgrades a library a running service uses, it opens a full-screen dialog. OhMyDebn sets neither `NEEDRESTART_MODE` nor `DEBIAN_FRONTEND`, so an update could stop there, and in the update GUI, with its terminal collapsed, it would look hung. `sudo needrestart` on the Debian 13 VM found nothing outdated, so the dialog couldn't be shown on demand.

Reproduce in a VM first (hold back a library upgrade, then update). If it stalls, run OhMyDebn's apt calls with `NEEDRESTART_MODE=l` (list only), next to `reboot-notice.sh`'s own notice.

## Tailscale and Cloudflare WARP without systemd: make them work

Without systemd, neither service starts: Tailscale's package starts `tailscaled` only through a systemd unit, and `cloudflare-warp`'s postinst only enables `warp-svc` with `systemctl`. Since 4.17.0 their installers and launchers say so and install nothing (`bin/ohmydebn-require-systemd`), and the docs say so too. Making them actually work on Devuan, LCOS and sysvinit MX Linux would take an init script for each service, packaged properly (per AGENTS.md) and tested in a VM. Worth it only if users ask.

## Remote Desktop Server on LCOS: make it work

LCOS replaces Xorg with XLibre, and Debian's `xorgxrdp` needs Xorg's `xserver-xorg-core`, so apt can't install it there. Since 4.17.0 the installer asks apt first (a simulation) and explains instead (`bin/ohmydebn-remote-desktop-server-install`); `tests/distro-checks.py` lists it as known. To make it work:

- On XLibre, install `xrdp` alone with its Xvnc backend (`tigervnc-standalone-server`), which doesn't depend on the X server's ABI. That needs sesman configuration and a VM test.
- Or ask LCOS whether they package an `xorgxrdp` built for XLibre.

## i386 notice on every apt update

On distros with i386 multiarch turned on (MX Linux and LMDE by default), every apt update prints "Notice: Skipping acquire of configured file 'main/binary-i386/Packages' as repository 'https://packages.ohmydebn.org trixie InRelease' doesn't support architecture 'i386'". It's harmless but noisy.

Add an `Architectures: <dpkg --print-architecture>` line to `/etc/apt/sources.list.d/ohmydebn.sources`. `install.sh` writes that file only when it's missing, so existing installs need an idempotent step that adds the line when it's absent (`ohmydebn-channel` rewrites only the URIs line, so it keeps it). Check Raspberry Pi OS (arm64) too.

## Firefox on Ubuntu, Mint and Pop!_OS

The Firefox menu item installs Debian's `firefox-esr`, which Ubuntu, Linux Mint and Pop!_OS don't have. Since 4.17.0 it says so and points to Install > Package (`bin/ohmydebn-pkg-available`). Mint and Pop!_OS have a real Firefox deb named `firefox` (Ubuntu's `firefox` only installs the snap), and Power User mode removes `firefox*` there, so on those two the menu can't put back the Firefox it removed. Supporting `firefox` means a `firefox` entry in `bin/ohmydebn-browser-set-default` with the binary its package registers with update-alternatives and its desktop id (check both on a Mint VM, not by guessing), then the launcher and installer picking `firefox-esr` or `firefox` as Chromium's do with their two names, and tests.

## Proposed, not yet agreed: removed-but-not-purged apps

`dpkg -s` returns 0 for a package that was removed but not purged (state `rc`), so an installer that checks it can think an app is still installed. A helper such as `ohmydebn-pkg-installed`, built on `dpkg-query -W -f '${db:Status-Status}'`, would let installers and launchers check for `installed` instead. The `-remove` scripts would keep `dpkg -s`.
