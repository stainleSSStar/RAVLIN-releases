#!/bin/sh
#
# RAVLIN CI test plumbing — runs chrooted in the freshly installed system
# (loop-mounted disk image, proc/sys/dev bind-mounted).
#
# This does not change what CI validates: the installation itself was
# performed by the real interactive void-installer. This script only turns
# on the serial console of the installed *test* system — kernel console
# plus a serial getty, the same setup a headless user would configure — so
# the QEMU boot test (ci/verify-install.exp) can observe and log in to it.

set -e

echo "ravlin-ci: serial console on the installed kernel cmdline"
echo 'GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0"' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo "ravlin-ci: serial login (agetty-ttyS0)"
# Note: the stock agetty-serial service derives the tty from its own
# directory name (tty=${PWD##*-}) and would try to open a device called
# "serial". The correct service for the serial port is agetty-ttyS0.
if [ -d /etc/sv/agetty-ttyS0 ]; then
    ln -sf /etc/sv/agetty-ttyS0 /etc/runit/runsvdir/default/agetty-ttyS0
else
    mkdir -p /etc/sv/agetty-ttyS0
    printf '#!/bin/sh\nexec agetty -L ttyS0 115200 vt100\n' > /etc/sv/agetty-ttyS0/run
    chmod 755 /etc/sv/agetty-ttyS0/run
    ln -sf /etc/sv/agetty-ttyS0 /etc/runit/runsvdir/default/agetty-ttyS0
fi

sync
echo "RAVLIN_SERIAL_READY"
