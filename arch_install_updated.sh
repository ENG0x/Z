
#!/bin/bash

# إيقاف السكربت عند حدوث أي خطأ
set -e

# ----------------------------------------
# 1. تعريف الأقراص
# ----------------------------------------
SSD="/dev/nvme0n1"  # القرص الرئيسي (SSD)
HDD="/dev/sda"      # القرص الثانوي (HDD) للهوم

# ----------------------------------------
# 2. التحقق من الأدوات والأقراص
# ----------------------------------------
echo "التحقق من الأدوات المطلوبة..."
for cmd in wipefs sgdisk parted mkfs.ext4 mkfs.fat pacstrap genfstab; do
  command -v $cmd >/dev/null || { echo "الأداة $cmd غير مثبتة. يرجى تثبيتها أولاً."; exit 1; }
done

echo "التحقق من الأقراص..."
lsblk | grep -q "$SSD" || { echo "القرص $SSD غير موجود."; exit 1; }
lsblk | grep -q "$HDD" || { echo "القرص $HDD غير موجود."; exit 1; }

# ----------------------------------------
# 3. تأكيد حذف البيانات
# ----------------------------------------
read -p "هل تريد فعلاً حذف جميع البيانات على ${SSD} و${HDD}? [y/N]: " confirm
[[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "تم الإلغاء."; exit 1; }

echo "تهيئة الأقراص وحذف البيانات السابقة..."
wipefs -a "$SSD"
wipefs -a "$HDD"
sgdisk --zap-all "$SSD"
sgdisk --zap-all "$HDD"

# ----------------------------------------
# 4. تقسيم القرص (SSD)
# ----------------------------------------
echo "تقسيم القرص SSD..."
parted -s "$SSD" mklabel gpt
parted -s "$SSD" mkpart primary fat32 1MiB 512MiB
parted -s "$SSD" mkpart primary ext4 512MiB 100%

echo "تهيئة الأقسام..."
mkfs.fat -F32 "${SSD}1"
mkfs.ext4 "${SSD}2"

# ----------------------------------------
# 5. تقسيم القرص (HDD)
# ----------------------------------------
echo "تقسيم القرص HDD..."
parted -s "$HDD" mklabel gpt
parted -s "$HDD" mkpart primary ext4 1MiB 100%

mkfs.ext4 "${HDD}1"

# ----------------------------------------
# 6. تركيب الأقسام
# ----------------------------------------
echo "تركيب الأقسام..."
mount "${SSD}2" /mnt
mkdir -p /mnt/boot
mount "${SSD}1" /mnt/boot

mkdir -p /mnt/home
mount "${HDD}1" /mnt/home

# ----------------------------------------
# 7. تثبيت النظام الأساسي
# ----------------------------------------
echo "تثبيت النظام الأساسي..."
pacstrap /mnt base base-devel linux linux-firmware neovim git networkmanager sudo efibootmgr firefox telegram-desktop

echo "إضافة تعريفات الجهاز..."
pacstrap /mnt linux-headers sof-firmware alsa-utils pulseaudio pavucontrol intel-ucode libinput xf86-input-synaptics fprintd

echo "إنشاء ملف fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# ----------------------------------------
# 8. إعداد النظام الأساسي مع Hyprland و SDDM
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
echo "تثبيت كلمة مرور المستخدم..."
passwd ziyad  # سيطلب منك إدخال كلمة مرور
echo "تثبيت كلمة مرور المستخدم root..."
passwd  # سيطلب منك إدخال كلمة مرور

# ضبط sudo
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# تثبيت مدير الإقلاع Systemd-boot
bootctl --path=/boot install

# إعداد ملفات الإقلاع
cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 0
editor no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "${SSD}2") rw quiet loglevel=3
ENTRY

# تمكين الخدمات الأساسية
systemctl enable NetworkManager

# تثبيت Hyprland و Wayland
pacman -S --noconfirm hyprland wayland xdg-desktop-portal-hyprland wayland-utils grim slurp mako wofi rofi kitty thunar thunar-volman gvfs zsh

# تعيين Zsh كشل افتراضي للمستخدمين
chsh -s /bin/zsh root
chsh -s /bin/zsh ziyad

# تثبيت Oh My Zsh
sudo -u ziyad bash -c "
sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" --unattended
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k
sed -i 's/ZSH_THEME=\".*\"/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/' ~/.zshrc
echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> ~/.zshrc
"

# إعداد الطرفية الافتراضية
echo "تخصيص الطرفية Kitty..."
mkdir -p /home/ziyad/.config/kitty
cat > /home/ziyad/.config/kitty/kitty.conf <<KITTY
font_size 14.0
background_opacity 0.9
scrollback_lines 10000
color_scheme solarized_dark
KITTY
chown -R ziyad:ziyad /home/ziyad/.config/kitty
EOF

# ----------------------------------------
# 9. إنهاء التثبيت
# ----------------------------------------
echo "تم الانتهاء من الإعداد! أعد التشغيل الآن."
umount -R /mnt
reboot
