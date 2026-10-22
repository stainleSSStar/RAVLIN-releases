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
if [ ! -d /etc/sv/agetty-serial ]; then
    mkdir -p /etc/sv/agetty-serial
    printf '#!/bin/sh\nexec agetty 115200 ttyS0\n' > /etc/sv/agetty-serial/run
    chmod 755 /etc/sv/agetty-serial/run
fi
ln -sf /etc/sv/agetty-serial /etc/runit/runsvdir/default/agetty-serial

echo "ravlin-ci: serial console on the installed kernel cmdline"
echo 'GRUB_CMDLINE_LINUX="console=ttyS0"' >> /etc/default/grub
update-grub

sync
echo "RAVLIN_CHROOT_DONE"
