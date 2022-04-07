#!/bin/bash


# settings

export IMG_SIZE=6G
export ESP_SIZE=512M
export DISTNAME=jammy
export REPO_URL=http://jp.archive.ubuntu.com/ubuntu
export HOSTNAME=jammy
export USERNAME=ubuntu

# packages

export PACKAGES="\
linux-image-generic shim-signed grub-efi-amd64-signed mokutil \
network-manager ufw avahi-daemon ssh bash-completion ubuntu-desktop"


command -v parted > /dev/null 2>&1
if [ $? -ne 0 ]; then
    apt install parted
fi

command -v debootstrap > /dev/null 2>&1
if [ $? -ne 0 ]; then
    apt install debootstrap
fi

command -v mkfs.vfat > /dev/null 2>&1
if [ $? -ne 0 ]; then
    apt install dosfstools
fi

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

fallocate -l $IMG_SIZE img
parted -s -a opt img mklabel gpt
parted -s -a opt img mkpart fat32  0% $ESP_SIZE
parted -s -a opt img mkpart ext4 $ESP_SIZE 100%
parted -s -a opt img set 1 boot on
parted -s -a opt img set 1 esp  on

losetup -P $(losetup -f) img

PART1=$(losetup -l | grep $(pwd)/img | awk '{ print $1 }')p1
PART2=$(losetup -l | grep $(pwd)/img | awk '{ print $1 }')p2
echo $PART1
echo $PART2

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

export DEBIAN_FRONTEND=noninteractive
debootstrap $DISTNAME mnt $REPO_URL

mount -t proc none mnt/proc
mount -t sysfs none mnt/sys
mount -t devtmpfs none mnt/dev

echo -e "$UUID1\t/boot/efi\tvfat\tumask=0077\t0\t0" >> mnt/etc/fstab
echo -e "$UUID2\t/\text4\terrors=remount-ro\t0\t1"  >> mnt/etc/fstab
echo -e "tmpfs\t/tmp\ttmpfs\tdefaults\t0\t0"        >> mnt/etc/fstab

echo $HOSTNAME > mnt/etc/hostname
chroot mnt sh -c "hostname $(cat /etc/hostname)"

export HEADER="export DEBIAN_FRONTEND=noninteractive &&"
chroot mnt sh -c "${HEADER} apt update && apt upgrade -y"
chroot mnt sh -c "${HEADER} apt install ${PACKAGES} -y"
chroot mnt sh -c "${HEADER} apt clean && rm -rf /var/lib/apt/lists/*"

chroot mnt sh -c "grub-install"
chroot mnt sh -c "sed -i -e '/^GRUB_CMDLINE_LINUX=/s/\"\"/\"systemd.show_status=1 modprobe.blacklist=nouveau\"/g' /etc/default/grub"
chroot mnt sh -c "sed -i -e '/^GRUB_CMDLINE_LINUX=/a GRUB_GFXPAYLOAD_LINUX=text' /etc/default/grub"
chroot mnt update-grub

cp NetworkManager.yaml mnt/etc/netplan/NetworkManager.yaml

chroot mnt sh -c "adduser ${USERNAME}"
chroot mnt sh -c "gpasswd -a ${USERNAME} sudo"
chroot mnt sh -c "ufw limit ssh && yes | ufw enable ; ufw status"
chroot mnt

umount mnt/dev
umount mnt/sys
umount mnt/proc
umount mnt/boot/efi
umount -l mnt
rm -rf mnt
losetup -D
