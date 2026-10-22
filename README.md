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
- Anywhere else (macOS, other Linux, CI), it automatically runs inside the official `ghcr.io/void-linux/void-glibc` container (`--privileged`, required by mklive).

Output: `ravlin-live-x86_64-0.1.0.iso`.

Useful overrides:

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

### Repository layout

```
├── build.sh              # entry point: fetches void-mklive, assembles the ISO
├── packages.txt          # live ISO package list (on top of base-system)
├── postsetup.sh          # mklive hook: registers fish, sets root's shell
├── rootfs/               # overlay copied into the live image (-I)
│   ├── etc/
│   │   ├── os-release    # RAVLIN identity (survives updates & install)
│   │   ├── issue, motd   # live session branding & instructions
│   │   ├── shells        # valid login shells
│   │   ├── hostname      # default hostname: ravlin
│   │   ├── default/useradd   # new users get SHELL=/usr/bin/fish
│   │   └── skel/.config/fish/config.fish   # fish prompt for new users
│   └── root/.config/fish/config.fish       # fish prompt for root
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
- **bash stays installed.** Removing it breaks virtually every system script. fish is the *default shell* (login shell of root and new users), not the only binary on disk.
- **No sudo alternative added.** `base-system` ships sudo already; nothing extra needed.
- **Firmware scope.** Network (wifi+ethernet) and sound firmware are included per the distro's goals. For full blobs (AMD/Intel/NVIDIA GPU microcode etc.) add `linux-firmware` to `packages.txt`. CPU microcode (`intel-ucode` / `amd-ucode`) is a reasonable optional addition.
- **os-release branding persists.** Void's `/etc/os-release` is a symlink to `/usr/lib/os-release`; the overlay replaces it with a regular file, so package updates don't clobber it.

## Roadmap

- [ ] TTY-only core (done — this repo)
- [ ] Optional CPU microcode packages
- [ ] RAVLIN metapackage in a hosted xbps repository (would make network-source installs equal to local installs)
- [ ] Graphical expansion (wayland session, Sway?) — later

## Credits

- [Void Linux](https://voidlinux.org) — the base distribution
- [void-mklive](https://github.com/void-linux/void-mklive) — the live image generator and the console installer
