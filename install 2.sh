#!/bin/bash

set -e

# ----------------------------------------
# 1. تعريف الأقراص والأقسام
# ----------------------------------------
SSD="/dev/neo"  # غير الاسم إذا اختلف
HDD="/dev/sda"  # هذا القرص للهوم

# ----------------------------------------
# 2. تقسيم القرص (SSD)
# ----------------------------------------
echo "تقسيم القرص SSD..."
parted -s "$SSD" mklabel gpt
parted -s "$SSD" mkpart primary fat32 1MiB 512MiB
parted -s "$SSD" set 1 esp on
parted -s "$SSD" mkpart primary ext4 512MiB 100%

echo "تهيئة الأقسام..."
mkfs.fat -F32 "${SSD}1"
mkfs.ext4 "${SSD}2"

# ----------------------------------------
# 3. تقسيم القرص (HDD)
# ----------------------------------------
echo "تقسيم القرص HDD..."
parted -s "$HDD" mklabel gpt
parted -s "$HDD" mkpart primary ext4 1MiB 100%

mkfs.ext4 "${HDD}1"

# ----------------------------------------
# 4. تركيب الأقسام
# ----------------------------------------
echo "تركيب الأقسام..."
mount "${SSD}2" /mnt
mkdir -p /mnt/boot
mount "${SSD}1" /mnt/boot

mkdir -p /mnt/home
mount "${HDD}1" /mnt/home

# ----------------------------------------
# 5. تثبيت النظام الأساسي
# ----------------------------------------
echo "تثبيت النظام الأساسي..."
pacstrap /mnt base base-devel linux linux-firmware neovim git networkmanager sudo efibootmgr firefox telegram-desktop neovim

echo "إضافة تعريفات الجهاز..."
pacstrap /mnt linux-headers sof-firmware alsa-utils pulseaudio pavucontrol intel-ucode libinput xf86-input-synaptics fprintd

echo "إنشاء ملف fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# ----------------------------------------
# 6. إعداد النظام الأساسي
# ----------------------------------------
arch-chroot /mnt /bin/bash <<EOF
# إعداد المنطقة الزمنية
ln -sf /usr/share/zoneinfo/Asia/Riyadh /etc/localtime
hwclock --systohc

# إعداد اللغة
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
locale-gen

# إعداد الكيبورد
echo "FONT=lat9w-16" >> /etc/vconsole.conf
localectl set-keymap us
localectl set-x11-keymap us,ara

# إعداد اسم الجهاز
echo "arch-system" > /etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\tarch-system.localdomain\tarch-system" > /etc/hosts

# إضافة مستخدم جديد مع صلاحيات sudo
useradd -m -G wheel -s /bin/bash ziyad
echo "ENG.ZIYAD:asad" | chpasswd  # استبدل <> بكلمة مرورك
echo "تثبيت كلمة مرور المستخدم root..."
echo "root:ZIYAD0540850037" | chpasswd  # استبدل <> بكلمة مرورك

# ضبط sudo
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# تثبيت مدير الإقلاع Systemd-boot
bootctl --path=/boot install

# إعداد ملفات الإقلاع
cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 5
editor no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "${SSD}2") rw
ENTRY

# تمكين الخدمات الأساسية
systemctl enable NetworkManager
systemctl enable fprintd.service

# تخصيص pacman لإضافة Candy، التنزيل المتعدد، والتحقق من التواقيع
sed -i '/#Color/a Color' /etc/pacman.conf
sed -i '/#Color/a ILoveCandy' /etc/pacman.conf
sed -i '/#ParallelDownloads/a ParallelDownloads = 5' /etc/pacman.conf
sed -i '/#SigLevel/a SigLevel = Required DatabaseOptional' /etc/pacman.conf
sed -i '/#LocalFileSigLevel/a LocalFileSigLevel = Optional' /etc/pacman.conf

# تثبيت yay (AUR Helper)
cd /home/ziyad
sudo -u ziyad bash -c "
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
"
EOF

# ----------------------------------------
# 7. إنهاء التثبيت
# ----------------------------------------
echo "تم الانتهاء من الإعداد! أعد التشغيل الآن."
umount -R /mnt
reboot