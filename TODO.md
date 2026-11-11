# TODO

Work deferred during 4.16.0 testing, for the next release. Each item says what's wrong, where, and the likely fix; check the code before relying on line numbers.

## needrestart could stall updates (unconfirmed)

Debian's `docker.io` Recommends `needrestart`, so installing Docker on Debian brings it in. By default it's interactive: after an apt run that upgrades a library a running service uses, it opens a full-screen dialog. OhMyDebn sets neither `NEEDRESTART_MODE` nor `DEBIAN_FRONTEND`, so an update could stop there, and in the update GUI, with its terminal collapsed, it would look hung. `sudo needrestart` on the Debian 13 VM found nothing outdated, so the dialog couldn't be shown on demand.

Reproduce in a VM first (hold back a library upgrade, then update). If it stalls, run OhMyDebn's apt calls with `NEEDRESTART_MODE=l` (list only), next to `reboot-notice.sh`'s own notice.

## Tailscale and Cloudflare WARP without systemd: make them work

Without systemd, neither service starts: Tailscale's package starts `tailscaled` only through a systemd unit, and `cloudflare-warp`'s postinst only enables `warp-svc` with `systemctl`. Since 4.17.0 their installers and launchers say so and install nothing (`bin/ohmydebn-require-systemd`), and the docs say so too. Making them actually work on Devuan, LCOS and sysvinit MX Linux would take an init script for each service, packaged properly (per AGENTS.md) and tested in a VM. Worth it only if users ask.

## Remote Desktop Server on LCOS: make it work

LCOS replaces Xorg with XLibre, and Debian's `xorgxrdp` needs Xorg's `xserver-xorg-core`, so apt can't install it there. Since 4.17.0 the installer asks apt first (a simulation) and explains instead (`bin/ohmydebn-remote-desktop-server-install`); `tests/distro-checks.py` lists it as known. To make it work:

- On XLibre, install `xrdp` alone with its Xvnc backend (`tigervnc-standalone-server`), which doesn't depend on the X server's ABI. That needs sesman configuration and a VM test.
- Or ask LCOS whether they package an `xorgxrdp` built for XLibre.

## Proposed, not yet agreed: removed-but-not-purged apps

`dpkg -s` returns 0 for a package that was removed but not purged (state `rc`), so an installer that checks it can think an app is still installed. A helper such as `ohmydebn-pkg-installed`, built on `dpkg-query -W -f '${db:Status-Status}'`, would let installers and launchers check for `installed` instead. The `-remove` scripts would keep `dpkg -s`.
