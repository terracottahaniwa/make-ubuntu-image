#!/bin/bash

if [ -d mnt ]; then
  umount mnt/dev
  umount mnt/sys
  umount mnt/proc
  umount mnt/root/efi
  umount -l mnt
  rm -rf mnt
  losetup -D
fi

if [ -f img ]; then
  rm -f img
fi

fallocate -l 6G img
parted -s -a opt img mklabel gpt
parted -s -a opt img mkpart fat32  0% 512M
parted -s -a opt img mkpart ext4 512M 100%
parted -s -a opt img set 1 boot on
parted -s -a opt img set 1 esp  on

losetup -P $(losetup -f) img

PART1=$(losetup -l | grep $(pwd)/img | awk '{ print $1 }')p1
PART2=$(losetup -l | grep $(pwd)/img | awk '{ print $1 }')p2
echo $PART1
echo $PART2

DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install dosfstools debootstrap -y
mkfs.vfat -F 32 $PART1
mkfs.ext4       $PART2

UUID1=$(blkid -s UUID $PART1 | awk '{ print $2 }')
UUID2=$(blkid -s UUID $PART2 | awk '{ print $2 }')
echo $UUID1
echo $UUID2

mkdir mnt
mount $PART2 mnt
mkdir -p mnt/boot/efi
mount -o umask=0077 $PART1 mnt/boot/efi
mount -t proc none mnt/proc
mount -t sysfs none mnt/sys
mount -t devtmpfs none mnt/dev

debootstrap hirsute mnt http://archive.ubuntu.com/ubuntu

echo "$UUID1\t/boot/efi\tvfat\tumask=0077\t0\t0" >> mnt/etc/fstab
echo "$UUID2\t/\text4\terrors=remount-ro\t0\t1"  >> mnt/etc/fstab
echo "tmpfs\t/tmp\ttmpfs\tdefaults\t0\t0"        >> mnt/etc/fstab

chroot mnt sh -c "export DEBIAN_FRONTEND=noninteractive && apt update && apt upgrade -y"
chroot mnt sh -c "export DEBIAN_FRONTEND=noninteractive && apt install linux-image-generic shim-signed grub-efi-amd64-signed mokutil -y"
chroot mnt sh -c "export DEBIAN_FRONTEND=noninteractive && apt install network-manager ufw avahi-daemon ssh bash-completion ubuntu-desktop -y"
chroot mnt sh -c "export DEBIAN_FRONTEND=noninteractive && apt clean"

chroot mnt sh -c "grub-install"
chroot mnt sh -c "sed -i -e 's/^gfxpayload_dynamic=\"1\"$/gfxpayload_dynamic=\"0\"/g' /etc/grub.d/10_linux"
chroot mnt sh -c "sed -i -e '/^GRUB_CMDLINE_LINUX=/s/\"\"/\"systemd.show_status=1 modprobe.blacklist=nouveau\"/g' /etc/default/grub"
chroot mnt update-grub

chroot mnt sh -c "echo 'network:'                   >> /etc/netplan/NetworkManager.yaml"
chroot mnt sh -c "echo '  version: 2'               >> /etc/netplan/NetworkManager.yaml"
chroot mnt sh -c "echo '  renderer: NetworkManager' >> /etc/netplan/NetworkManager.yaml"
chroot mnt sh -c "echo 'hirsute' > /etc/hostname"
chroot mnt sh -c "hostname $(echo /etc/hostname)"

chroot mnt sh -c "adduser ubuntu"
chroot mnt sh -c "gpasswd -a ubuntu sudo"
chroot mnt sh -c "ufw allow ssh && yes | ufw enable ; ufw status"
chroot mnt

umount mnt/dev
umount mnt/sys
umount mnt/proc
umount mnt/boot/efi
umount -l mnt
rm -rf mnt
losetup -D
