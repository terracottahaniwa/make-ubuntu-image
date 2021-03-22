#!/bin/bash

umount mnt/root/efi
umount mnt/dev
umount mnt/sys
umount mnt/proc
umount -l mnt
losetup -D
rm -f img
rm -rf mnt

fallocate -l 4G img
parted -s -a opt img mklabel gpt
parted -s -a opt img mkpart fat32  0% 512M
parted -s -a opt img mkpart ext4 512M 100%
parted -s -a opt img set 1 boot on
parted -s -a opt img set 1 esp  on

losetup -P $(losetup -f) img

PART1=$(losetup -l | grep $(pwd)/img | awk '{ print $1 }')p1
PART2=$(losetup -l | grep $(pwd)/img | awk '{ print $1 }')p2

apt install dosfstools
mkfs.vfat -F 32 $PART1
mkfs.ext4       $PART2

mkdir mnt
mount $PART2 mnt

debootstrap groovy mnt http://jp.archive.ubuntu.com/ubuntu

echo $PART1
echo $PART2

mkdir -p mnt/boot/efi
mount -o umask=0077 $PART1 mnt/boot/efi

mount -t proc none mnt/proc
mount -t sysfs none mnt/sys
mount -t devtmpfs none mnt/dev

UUID1=$(blkid -s UUID $PART1 | awk '{ print $2 }')
UUID2=$(blkid -s UUID $PART2 | awk '{ print $2 }')

echo "$UUID1\t/boot/efi\tvfat\tumask=0077\t0\t0" >> mnt/etc/fstab
echo "$UUID2\t/\text4\terrors=remount-ro\t0\t1"  >> mnt/etc/fstab

chroot mnt sh -c "export DEBIAN_FRONTEND=noninteractive && apt update && apt upgrade -y"
chroot mnt sh -c "export DEBIAN_FRONTEND=noninteractive && apt install linux-image-generic grub-efi bash-completion ufw ssh avahi-daemon -y"

chroot mnt sh -c "grub-install"
chroot mnt sh -c "sed -i.old -e 's/gfxpayload_dynamic=\"1\"/gfxpayload_dynamic=\"0\"/g'                              /etc/grub.d/10_linux"
chroot mnt sh -c "sed -i     -e '/^vt_handoff=\"1\"$/a GRUB_CMDLINE_LINUX=\"consoleblank=60 systemd.show_status=1\"' /etc/grub.d/10_linux"
chroot mnt update-grub

chroot mnt sh -c "echo 'network:'             >> /etc/netplan/networkd.yaml"
chroot mnt sh -c "echo '  version: 2'         >> /etc/netplan/networkd.yaml"
chroot mnt sh -c "echo '  renderer: networkd' >> /etc/netplan/networkd.yaml"
chroot mnt sh -c "echo '  ethernets:'         >> /etc/netplan/networkd.yaml"
chroot mnt sh -c "echo '    enp3s0:'          >> /etc/netplan/networkd.yaml"
chroot mnt sh -c "echo '      tdhcp4: true'   >> /etc/netplan/networkd.yaml"
chroot mnt sh -c "echo 'groovy' > /etc/hostname"
chroot mnt sh -c "hostname $(echo /etc/hostname)"

chroot mnt sh -c "adduser ubuntu"
chroot mnt sh -c "gpasswd -a ubuntu sudo"
chroot mnt sh -c "ufw allow ssh && yes | ufw enable ; ufw status"
chroot mnt

umount mnt/boot/efi
umount mnt/dev
umount mnt/sys
umount mnt/proc
umount -l mnt
losetup -D
