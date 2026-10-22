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
# Live services: DHCP on any NIC, wifi supplicant, power button.
SERVICES="dhcpcd wpa_supplicant acpid"
# The anon live user gets fish too.
KCMDLINE="live.shell=/usr/bin/fish"

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

# Package list: one package per line, comments and blank lines allowed.
mapfile -t PKG_LINES < <(grep -vE '^[[:space:]]*(#|$)' "$SCRIPT_DIR/packages.txt")
PKGS="${PKG_LINES[*]}"
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
    git -C "$MKLIVE_DIR" checkout --quiet --detach "$MKLIVE_REF"

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
    "$runner" run --rm --privileged \
        -v "$SCRIPT_DIR":/ravlin -w /ravlin \
        "$CONTAINER_IMAGE" \
        bash /ravlin/build.sh --native
}

main() {
    if [ "${1:-}" = "--native" ]; then
        run_native || die "native build failed (xbps-install not found — not a Void host?)"
    elif command -v xbps-install >/dev/null 2>&1; then
        run_native
    else
        run_container
    fi
}

main "$@"
