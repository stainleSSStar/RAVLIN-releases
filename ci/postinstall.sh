#!/bin/sh
# RAVLIN CI post-install hook — runs inside the live image's initramfs as the
# autoinstaller end_script, with $target pointing at the freshly installed
# system and proc/sys/dev still bind-mounted into it.
#
# Deliberately uses only binaries guaranteed to exist in the dracut
# autoinstaller initramfs (mkdir, chmod, chroot, xbps-uhelper, echo);
# everything else happens inside the target chroot via postinstall-chroot.sh.

set -e

target="${target:-/mnt}"
srv="http://10.0.2.2:8000"

echo "ravlin-ci: fetching branding files into ${target}"

mkdir -p "${target}/tmp" \
         "${target}/etc/default" \
         "${target}/etc/skel/.config/fish" \
         "${target}/root/.config/fish"

xbps-uhelper fetch "${srv}/postinstall-chroot.sh>${target}/tmp/postinstall-chroot.sh"
xbps-uhelper fetch "${srv}/etc/os-release>${target}/etc/os-release"
xbps-uhelper fetch "${srv}/etc/shells>${target}/etc/shells"
xbps-uhelper fetch "${srv}/etc/default/useradd>${target}/etc/default/useradd"
xbps-uhelper fetch "${srv}/etc/skel/.config/fish/config.fish>${target}/etc/skel/.config/fish/config.fish"
xbps-uhelper fetch "${srv}/root/.config/fish/config.fish>${target}/root/.config/fish/config.fish"

chmod 755 "${target}/tmp/postinstall-chroot.sh"

echo "ravlin-ci: running postinstall inside the target"
chroot "${target}" /tmp/postinstall-chroot.sh

echo "RAVLIN_POSTINSTALL_DONE"
