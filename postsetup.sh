#!/bin/sh
#
# RAVLIN postsetup — mklive.sh -x hook.
# Receives the assembled live ROOTFS path as $1, after packages are
# installed and before the initramfs is generated.

set -e

ROOTFS="$1"

# Register fish as a valid login shell. mklive changes the root shell via
# chsh only if it accepts the target, and chsh consults /etc/shells.
echo "ravlin: registering /usr/bin/fish in /etc/shells"
touch "$ROOTFS/etc/shells"
grep -qx '/usr/bin/fish' "$ROOTFS/etc/shells" || echo '/usr/bin/fish' >> "$ROOTFS/etc/shells"

# Fish as the root shell, on the live image and on any system installed
# from it (void-installer copies the live rootfs).
echo "ravlin: setting fish as the root shell"
chroot "$ROOTFS" chsh -s /usr/bin/fish root

echo "ravlin: postsetup done"
