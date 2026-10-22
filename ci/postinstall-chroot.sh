#!/bin/sh
# RAVLIN CI postinstall — runs chrooted in the freshly installed system
# (proc/sys/dev are mounted). Uses the target's own tooling.

set -e

echo "ravlin-ci: fish as login shell for root and the CI user"
chsh -s /usr/bin/fish root
chsh -s /usr/bin/fish ravlin

echo "ravlin-ci: fish config for the CI user home"
mkdir -p /home/ravlin/.config/fish
cp /etc/skel/.config/fish/config.fish /home/ravlin/.config/fish/config.fish
chown -R ravlin:ravlin /home/ravlin/.config

echo "ravlin-ci: enabling the same services as the live image"
for svc in dhcpcd wpa_supplicant acpid; do
    [ -d "/etc/sv/${svc}" ] && \
        ln -sf "/etc/sv/${svc}" "/etc/runit/runsvdir/default/${svc}"
done

echo "ravlin-ci: serial console for the boot test"
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

echo "ravlin-ci: serial console on the installed kernel cmdline"
echo 'GRUB_CMDLINE_LINUX="console=ttyS0"' >> /etc/default/grub
update-grub

sync
echo "RAVLIN_CHROOT_DONE"
