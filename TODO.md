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

## Tailscale and Cloudflare WARP without systemd

Neither works on Devuan, LCOS or sysvinit MX Linux. Tailscale hasn't since it was added in 4.2.0.

- Tailscale: the package starts `tailscaled` only through a systemd unit, so it never starts. `bin/ohmydebn-tailscale-install`'s last step, `tailscale set --operator`, then fails ("Failed to connect to local Tailscale daemon ... tailscaled.sock") and the script exits with an error. Opening it from the menu runs `tailscale systray`, which can't connect either. Seen on the 4.16.0 sysvinit MX fresh install.
- WARP: `cloudflare-warp`'s postinst calls `systemctl` ("systemctl: not found", "warp-svc.service is a disabled or a static unit, not starting it"), so `warp-svc` never starts. The Cloudflare One Client window then shows "Unable to connect" and "The application failed to initialized.", with no hint that systemd is the cause. Seen on the 4.16.0 LCOS fresh install.

The docs are wrong too: the Devuan section of `installation.md` says "Everything else in OhMyDebn works the same", and the MX sysvinit section points there.

Fix both together: either start scripts for the services (packaged properly, per AGENTS.md), or installers that refuse without systemd and say why. Then fix the docs.

## Remote Desktop Server on LCOS

Remote Desktop Server can't be installed on LCOS, and hasn't since it was added in 4.10.0. LCOS 1.0.0 replaces Xorg with XLibre (`xserver-xlibre-core` 2:25.1.9-1+lcos1), and Debian's `xorgxrdp` depends on `xorg-input-abi-24`, which only Xorg's `xserver-xorg-core` provides. So `apt install xrdp xorgxrdp` fails with "Unsatisfied dependencies" (`bin/ohmydebn-remote-desktop-server-install`). Nothing is left behind, because apt is the first change.

Options:

- Detect at runtime whether `xorgxrdp` can be installed (rather than checking the distro name) and refuse with a clear message.
- On XLibre, install `xrdp` alone with its Xvnc backend (`tigervnc-standalone-server`), which doesn't depend on the X server's ABI. That needs sesman configuration and a VM test.
- Ask LCOS whether they package an `xorgxrdp` built for XLibre.

Then update `utilities.md` and the LCOS section of `installation.md`.

## i386 notice on every apt update

On distros with i386 multiarch turned on (MX Linux and LMDE by default), every apt update prints "Notice: Skipping acquire of configured file 'main/binary-i386/Packages' as repository 'https://packages.ohmydebn.org trixie InRelease' doesn't support architecture 'i386'". It's harmless but noisy.

Add an `Architectures: <dpkg --print-architecture>` line to `/etc/apt/sources.list.d/ohmydebn.sources`. `install.sh` writes that file only when it's missing, so existing installs need an idempotent step that adds the line when it's absent (`ohmydebn-channel` rewrites only the URIs line, so it keeps it). Check Raspberry Pi OS (arm64) too.

## Proposed, not yet agreed: removed-but-not-purged apps

`dpkg -s` returns 0 for a package that was removed but not purged (state `rc`), so an installer that checks it can think an app is still installed. A helper such as `ohmydebn-pkg-installed`, built on `dpkg-query -W -f '${db:Status-Status}'`, would let installers and launchers check for `installed` instead. The `-remove` scripts would keep `dpkg -s`.
