# RAVLIN

A **minimal, TTY-only Linux distribution** based on [Void Linux](https://voidlinux.org), with **fish as the default shell** and working **wifi, LAN, and sound** out of the box. It boots to a console, ships an **interactive console installer**, and stays as small as possible.

> Status: `0.1.0` — TTY only. GUI/Wayland etc. may come later.

## What's in it

| Area | Choice |
|---|---|
| Base | Void Linux `base-system` (glibc, runit, xbps, kernel) |
| Shell | fish — default for root and all new users |
| Installer | `void-installer` — Void's interactive dialog-based console installer |
| Drivers | `linux-firmware-network` (wifi+ethernet blobs), `sof-firmware` + `alsa-ucm-conf` + `alsa-utils` (sound) |
| Networking | `dhcpcd` + `wpa_supplicant` (enabled by default) |
| Sound | `alsa-utils` with the `alsa` service enabled — mixer state is saved at shutdown and restored at boot |
| Bootloader | GRUB (BIOS + 32/64-bit EFI) |
| Display | none — TTY only, by design |

What is *deliberately not* included: X11/Wayland, display managers, NetworkManager, pipewire, tmux, chrony, cryptsetup, LVM, mdadm, accessibility tooling (all of which Void's standard `mkiso.sh` base image carries). bash and dash stay installed because system scripts (including the installer) need them — fish replaces them only as your *login* shell.

## Building the ISO

The build uses [void-mklive](https://github.com/void-linux/void-mklive) (pinned commit), so you need either a Void Linux host or Docker:

```sh
git clone https://github.com/stainleSSStar/RAVLIN.git
cd RAVLIN
bash build.sh
```

- On a **Void host**, the build runs natively.
- Anywhere else (macOS, other Linux, CI), it automatically runs inside the official `ghcr.io/void-linux/void-glibc` container (`--privileged`, required by mklive). The build script is Bash 3.2 compatible, so macOS's bundled shell can drive it; only the container itself needs bash, which the entrypoint installs on demand.

Output: `ravlin-live-x86_64-0.1.0.iso`.

Useful overrides (honoured on the native path *and* forwarded into the Docker/Podman path):

```sh
RAVLIN_MIRROR=https://repo-default.voidlinux.org/current bash build.sh  # pick a mirror
MKLIVE_REF=master bash build.sh                                          # track upstream mklive
```

### CI builds and releases

No local tooling needed — the repo ships a GitHub Actions workflow (`.github/workflows/build.yml`) that builds the ISO in the same privileged Void container void-mklive uses for its own CI, and can publish a release:

- **Manual build:** GitHub → *Actions* → *Build RAVLIN ISO* → *Run workflow*. Tick **"Also publish a GitHub release"** to publish the ISO as a release in one go.
- **Tag build:** push a tag like `v0.1.0` — the ISO is built and released automatically (`v*` tags trigger the release job).

Every release ships the ISO plus a `sha256sum.txt`. By default releases land on this repository's *Releases* page, which works with the built-in `GITHUB_TOKEN` and zero configuration. To publish into a separate releases repository instead, add two repository secrets:

| Secret | Value |
|---|---|
| `RELEASES_REPO` | e.g. `stainleSSStar/RAVLIN-releases` |
| `RELEASES_TOKEN` | a personal access token with `contents:write` on that repo |

#### What CI validates

Every build is gated on three QEMU jobs (software emulation — the runners have no KVM), all booting the actual ISO artifacts:

- **BIOS boot** — the ISO boots through its own bootloader chain (SeaBIOS → ISOLINUX → kernel), then over the serial console CI verifies: fish login shell with the RAVLIN config, `void-installer` present, RAVLIN `os-release`, `dhcpcd`/`wpa_supplicant` *running* (`sv status`, not just enabled), the ALSA stack detecting an emulated sound card (`aplay -l`), and the live hostname (`ravlin`, set by the patched vmklive boot hook).
- **UEFI boot** — the same ISO boots through the EFI chain (OVMF → GRUB EFI → kernel) to a working live session.
- **Install test** — the installation users actually perform: CI boots the live ISO, then drives the *real interactive `void-installer`* through its dialog menus (root password, bootloader, ext4 on `/`, **Local** source) onto a blank disk. The disk then boots through its own GRUB and the installed system is verified (fish, identity, services running, alsa service, package set) — including a *forced `base-files` reinstall* to prove the RAVLIN `os-release` survives package updates (the `preserve=` pattern in `/etc/xbps.d/49-ravlin-preserve.conf`).

Honest limits: tests run on emulated hardware (virtio disk/NIC, emulated HDA audio), so physical wifi radios, speakers and exotic firmware remain untested by CI. A serial console is enabled on the installed *test* system (test plumbing in `ci/postinstall-chroot.sh`) purely so the boot test can observe it — the installation itself is untouched.

### Repository layout

```
├── build.sh              # entry point: fetches void-mklive, assembles the ISO
├── packages.txt          # live ISO package list (on top of base-system)
├── postsetup.sh          # mklive hook: registers fish, sets root's shell
├── rootfs/               # overlay copied into the live image (-I)
│   ├── etc/
│   │   ├── os-release    # RAVLIN identity
│   │   ├── xbps.d/49-ravlin-preserve.conf  # keep os-release across base-files updates
│   │   ├── issue, motd   # live session branding & instructions
│   │   ├── shells        # valid login shells
│   │   ├── hostname      # default hostname: ravlin
│   │   ├── default/useradd   # new users get SHELL=/usr/bin/fish
│   │   └── skel/.config/fish/config.fish   # fish prompt for new users
│   └── root/.config/fish/config.fish       # fish prompt for root
├── ci/                   # QEMU/expect boot, install and verify scripts
│   ├── smoke-bios.exp    # BIOS boot test via the ISO's ISOLINUX bootloader
│   ├── smoke-uefi.exp    # UEFI boot test via the ISO's GRUB EFI bootloader
│   ├── install-ravlin.exp    # drives the real interactive void-installer
│   ├── verify-install.exp   # boots the installed disk via its own GRUB
│   └── postinstall-chroot.sh # CI-only serial-console test plumbing
└── .gitignore
```

`rootfs/usr/bin/void-installer` is generated at build time from void-mklive's `installer.sh` (with RAVLIN branding) — same mechanism `mkiso.sh` uses, minus the extra packages.

## Installing

1. Write the ISO to a USB stick and boot it:
   ```sh
   sudo dd if=ravlin-live-x86_64-0.1.0.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
2. Log in on the console as `root` (password `voidlinux`) — you land in fish.
3. Run:
   ```fish
   void-installer
   ```
   The installer walks you through keymap, locale, timezone, hostname, root password, user creation, partitioning (`cfdisk`/`fdisk`), mount points, GRUB, and services — fully interactive, no graphical anything.
4. Choose the default **local install** source when prompted (see note below).
5. Reboot into RAVLIN. Your user logs into fish.

### Important note on install sources

`void-installer` offers two sources:

- **Local (default)** — copies the live rootfs to disk. This is the RAVLIN install: fish everywhere, drivers, branding. Use this.
- **Network** — installs a stock Void `base-system` from a mirror and **does not include RAVLIN's package set** (fish, sound/wifi firmware, etc.), because it pulls the vanilla Void metapackage. Avoid it for now.

## Post-install quick reference

```fish
# wifi (WPA): edit /etc/wpa_supplicant/wpa_supplicant.conf, then:
wpa_passphrase "SSID" "password" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf
sudo ln -s /etc/sv/wpa_supplicant /var/service/   # if not already enabled

# sound
alsamixer    # unmute with M, raise with arrows

# packages
sudo xbps-install -S <pkg>
sudo xbps-remove <pkg>
```

## Design decisions

- **void-installer instead of a custom installer.** It is already an interactive, dialog-based console installer, maintained upstream and battle-tested. RAVLIN reuses it with branding rather than maintaining a fork.
- **xmirror is included.** void-installer's Mirror menu execs `xmirror`; it ships on the live image (the installer's local-install cleanup removes it from the target again), so every installer menu item works.
- **Serial console on the live image.** The live kernel cmdline carries `console=tty0 console=ttyS0`, so a live session is usable over a serial console (the vmklive live image enables a serial getty for it). Installed systems are untouched — the installer writes its own GRUB config.
- **bash stays installed.** Removing it breaks virtually every system script. fish is the *default shell* (login shell of root and new users), not the only binary on disk.
- **No sudo alternative added.** `base-system` ships sudo already; nothing extra needed.
- **Firmware scope.** Network (wifi+ethernet) and sound firmware are included per the distro's goals. For full blobs (AMD/Intel/NVIDIA GPU microcode etc.) add `linux-firmware` to `packages.txt`. CPU microcode (`intel-ucode` / `amd-ucode`) is a reasonable optional addition.
- **os-release branding persists — explicitly.** Void's `/etc/os-release` is a symlink owned by `base-files`, and the overlay copy alone is not enough: `cp` follows the symlink at the destination, so the identity would silently land in the package-owned `/usr/lib/os-release` and the next `base-files` update would revert it. `postsetup.sh` therefore replaces the symlink with the real RAVLIN file, and `/etc/xbps.d/49-ravlin-preserve.conf` (also part of the overlay, so it lands on installed systems too) tells xbps to preserve the path against the type-mismatch removal on future `base-files` updates. CI proves the whole chain with a forced `base-files` reinstall.
- **Live hostname is ravlin.** void-mklive's vmklive dracut hook rewrites `/etc/hostname` to `void-live` on every live boot (which the local-copy install would then inherit); the build patches that hook in the pinned checkout so the machine is called `ravlin` on the live image and after installation.
- **ALSA service enabled.** `alsa` is part of the enabled service set, so `alsamixer` changes are saved at shutdown and restored on the next boot.

## Roadmap

- [ ] TTY-only core (done — this repo)
- [ ] Optional CPU microcode packages
- [ ] RAVLIN metapackage in a hosted xbps repository (would make network-source installs equal to local installs)
- [ ] Graphical expansion (wayland session, Sway?) — later

## Credits

- [Void Linux](https://voidlinux.org) — the base distribution
- [void-mklive](https://github.com/void-linux/void-mklive) — the live image generator and the console installer
