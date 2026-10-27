#!/usr/bin/env bash
#
# RAVLIN live ISO builder.
#
# Wraps void-mklive's mklive.sh to produce a minimal, TTY-only, fish-first
# RAVLIN live image that ships void-installer, the interactive console
# installer, plus wifi/LAN/sound drivers and firmware.
#
# Usage:
#   ./build.sh              build natively (Void Linux host) or fall back to Docker
#   ./build.sh --native     internal: run the native build (used inside the container)
#
# Runs on Bash 3.2 (macOS) and newer; on non-Void hosts the build runs
# inside the official Void container (needs Docker or Podman).
#
# Environment overrides:
#   RAVLIN_ARCH     target architecture           (default: x86_64)
#   RAVLIN_MIRROR    XBPS repository              (default: https://repo-default.voidlinux.org/current)
#   MKLIVE_REF       void-mklive commit/tag to pin (default: pinned commit below)

set -euo pipefail

RAVLIN_VERSION="0.1.0"
ARCH="${RAVLIN_ARCH:-x86_64}"
MIRROR="${RAVLIN_MIRROR:-https://repo-default.voidlinux.org/current}"
MKLIVE_REPO="https://github.com/void-linux/void-mklive.git"
# Pin a known-good void-mklive snapshot; bump deliberately.
MKLIVE_REF="${MKLIVE_REF:-8ca31d112776fdbf7c1deb3dd7e15d87d6712db3}"
CONTAINER_IMAGE="ghcr.io/void-linux/void-glibc:latest"
# Live services: DHCP on any NIC, wifi supplicant, power button, and the
# alsa service so mixer settings (alsamixer) are restored at boot and
# saved again at shutdown.
SERVICES="dhcpcd wpa_supplicant acpid alsa"
# The anon live user gets fish too. console=ttyS0 makes the live image usable
# over a serial console: the vmklive dracut module enables agetty-ttyS0 when
# it sees console=ttyS0 on the kernel cmdline. CI boots the ISO through its
# own bootloaders and drives the installer over this serial console.
KCMDLINE="live.shell=/usr/bin/fish console=tty0 console=ttyS0,115200n8"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
MKLIVE_DIR="$BUILD_DIR/void-mklive"
OVERLAY="$SCRIPT_DIR/rootfs"
POSTSETUP="$SCRIPT_DIR/postsetup.sh"
ISO_NAME="ravlin-live-${ARCH}-${RAVLIN_VERSION}.iso"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$OVERLAY" ] || die "rootfs overlay not found: $OVERLAY"
[ -f "$POSTSETUP" ] || die "postsetup script not found: $POSTSETUP"
# mklive execs the postsetup hook and requires it to be executable; the git
# checkout may lack the bit if the repo was created via the GitHub API.
chmod +x "$POSTSETUP"

# Package list: one package per line; comment and blank lines are ignored.
# Deliberately no bash-4 constructs (e.g. mapfile) anywhere in this script:
# it must run on macOS's bundled Bash 3.2, which reaches run_container.
PKGS="$(awk 'NF && $1 !~ /^#/ {printf "%s ", $1}' "$SCRIPT_DIR/packages.txt")"
[ -n "$PKGS" ] || die "packages.txt contains no packages"

prepare_mklive() {
    command -v git >/dev/null 2>&1 || xbps-install -Sy git
    if [ ! -d "$MKLIVE_DIR/.git" ]; then
        log "Cloning void-mklive into $MKLIVE_DIR ..."
        mkdir -p "$BUILD_DIR"
        git clone --quiet "$MKLIVE_REPO" "$MKLIVE_DIR"
    fi
    log "Pinning void-mklive to $MKLIVE_REF"
    git -C "$MKLIVE_DIR" fetch --quiet origin || true
    # Resolve the ref against the remote first: a bare branch name such as
    # "master" must track origin/master, not the stale local ref left in
    # the cached clone by an earlier build.
    local ref="$MKLIVE_REF"
    if git -C "$MKLIVE_DIR" rev-parse -q --verify "refs/remotes/origin/${MKLIVE_REF}" >/dev/null 2>&1; then
        ref="refs/remotes/origin/${MKLIVE_REF}"
    fi
    git -C "$MKLIVE_DIR" checkout --quiet --force --detach "$ref" \
        || die "failed to check out pinned void-mklive ref $MKLIVE_REF"
    # Belt and braces: never build from anything but the pinned revision.
    local pinned head
    pinned="$(git -C "$MKLIVE_DIR" rev-parse "${ref}^{commit}")"
    head="$(git -C "$MKLIVE_DIR" rev-parse HEAD)"
    [ -n "$pinned" ] && [ -n "$head" ] \
        || die "could not resolve the void-mklive revision to build (git rev-parse failed)"
    [ "$pinned" = "$head" ] \
        || die "void-mklive HEAD ($head) does not match the pinned ref $MKLIVE_REF ($pinned)"

    # The vmklive dracut hook (dracut/vmklive/adduser.sh) rewrites
    # /etc/hostname to "void-live" on every live boot; that value would
    # also end up on systems installed from this image, because the
    # installer copies the live rootfs. Patch the pinned checkout so the
    # live image — and anything installed from it — is called ravlin.
    # (-i.bak is used instead of bare -i so this also works on BSD sed.)
    sed -i.bak 's/^echo void-live >/echo ravlin >/' "$MKLIVE_DIR/dracut/vmklive/adduser.sh"
    rm -f "$MKLIVE_DIR/dracut/vmklive/adduser.sh.bak"
    grep -q '^echo ravlin >' "$MKLIVE_DIR/dracut/vmklive/adduser.sh" \
        || die "failed to patch the live hostname hook in void-mklive"

    # Ship void-installer (Void's interactive console installer), the same way
    # mkiso.sh does, but branded for RAVLIN.
    local installer="$OVERLAY/usr/bin/void-installer"
    mkdir -p "$OVERLAY/usr/bin"
    sed -e "s/@@MKLIVE_VERSION@@/RAVLIN ${RAVLIN_VERSION}/" \
        -e "s/Void Linux installation/RAVLIN installation/g" \
        "$MKLIVE_DIR/installer.sh" > "$installer"
    chmod 755 "$installer"
}

run_native() {
    command -v xbps-install >/dev/null 2>&1 || return 1
    prepare_mklive
    log "Building RAVLIN ${RAVLIN_VERSION} (${ARCH}) ..."
    (cd "$MKLIVE_DIR" && ./mklive.sh \
        -a "$ARCH" \
        -o "$SCRIPT_DIR/$ISO_NAME" \
        -p "$PKGS" \
        -S "$SERVICES" \
        -I "$OVERLAY" \
        -x "$POSTSETUP" \
        -T "RAVLIN" \
        -C "$KCMDLINE" \
        -r "$MIRROR") || die "mklive.sh failed"
    [ -f "$SCRIPT_DIR/$ISO_NAME" ] || die "expected ISO was not produced: $SCRIPT_DIR/$ISO_NAME"
    log "Done: $SCRIPT_DIR/$ISO_NAME"
}

# Non-Void hosts build inside the official Void container. --privileged is
# required because mklive bind-mounts pseudofilesystems while assembling the rootfs.
run_container() {
    local runner=""
    command -v docker >/dev/null 2>&1 && runner=docker
    [ -z "$runner" ] && command -v podman >/dev/null 2>&1 && runner=podman
    [ -z "$runner" ] && die "not on a Void host and neither docker nor podman was found"

    log "Not a Void host — building inside $runner ($CONTAINER_IMAGE) ..."
    # The official void-glibc container is intentionally minimal: its
    # recipe installs only "xbps base-files dash coreutils grep run-parts
    # sed gawk" — no bash, which this build script needs. Bootstrap with
    # dash and install bash first if it is missing; fail with a clear
    # message if that is not possible.
    "$runner" run --rm --privileged \
        -e RAVLIN_ARCH="$ARCH" \
        -e RAVLIN_MIRROR="$MIRROR" \
        -e MKLIVE_REF="$MKLIVE_REF" \
        -v "$SCRIPT_DIR":/ravlin -w /ravlin \
        "$CONTAINER_IMAGE" \
        sh -c 'command -v bash >/dev/null 2>&1 || xbps-install -Sy bash || { echo "ERROR: failed to install bash in the container (network/repository reachable?)" >&2; exit 1; }; exec bash /ravlin/build.sh --native'
}

# NOTE: run_native must never be invoked as "run_native || die ..." — the
# function would then run with set -e suppressed and a failed step (e.g. the
# pinned void-mklive checkout) would leave the build to continue on whatever
# revision happens to be checked out.
main() {
    if [ "${1:-}" = "--native" ]; then
        command -v xbps-install >/dev/null 2>&1 \
            || die "native build requested, but xbps-install was not found (not a Void host?)"
        run_native
    elif command -v xbps-install >/dev/null 2>&1; then
        run_native
    else
        run_container
    fi
}

main "$@"
