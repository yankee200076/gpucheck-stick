#!/bin/bash
# Stage 1 (im chroot): Basissystem, Kernel, NVIDIA-Treiber, Desktop, Autologin.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

NV=595   # NVIDIA-Branch (>= 580). Canonical-signierte Open-Module -> Secure Boot ok.

cat > /etc/apt/sources.list.d/ubuntu.sources <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: resolute resolute-updates resolute-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu
Suites: resolute-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
# Keine Empfehlungen -> schlankes System
echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/90norecommends

echo gpucheck > /etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 gpucheck\n' > /etc/hosts

apt-get update
apt-get -y dist-upgrade

# Locale / Tastatur / Zeitzone
sed -i 's/^# *de_DE.UTF-8/de_DE.UTF-8/; s/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=de_DE.UTF-8' > /etc/default/locale
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
echo Europe/Berlin > /etc/timezone
cat > /etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="de"
XKBVARIANT="nodeadkeys"
XKBOPTIONS=""
BACKSPACE="guess"
EOF

# Kernel + Bootloader (signiert: shim -> grub -> kernel)
apt-get -y install linux-image-generic linux-firmware initramfs-tools \
    shim-signed grub-efi-amd64-signed grub-efi-amd64-bin efibootmgr mokutil \
    systemd-sysv udev kmod dbus sudo

# NVIDIA: vorgebaute, von Canonical signierte Open-Kernel-Module + Userspace.
# linux-modules-nvidia-*-open-generic erfüllt die Kernel-Abhängigkeit -> kein DKMS.
apt-get -y install linux-modules-nvidia-${NV}-open-generic nvidia-driver-${NV}-open \
    libnvidia-gl-${NV} nvidia-utils-${NV} nvidia-settings
if dpkg -l | grep -q '^ii  nvidia-dkms'; then
    echo "FEHLER: nvidia-dkms wurde gezogen (unsignierte Module!)"; exit 1
fi

# Desktop (XFCE, LightDM-Autologin) + Tools
apt-get -y install xorg xserver-xorg-video-all xfce4 xfce4-terminal xfce4-taskmanager \
    xfce4-notifyd thunar mousepad lightdm lightdm-gtk-greeter \
    fonts-dejavu-core adwaita-icon-theme gvfs zenity at-spi2-core \
    network-manager network-manager-gnome \
    pciutils usbutils lshw dmidecode lm-sensors smartmontools nvme-cli \
    vulkan-tools mesa-utils mesa-vulkan-drivers libvulkan1 vkmark glmark2-x11 \
    nvtop stress-ng jq bc gawk exfatprogs less nano htop tmux \
    python3 x11-xserver-utils xdotool

# Benutzer mit Autologin, sudo ohne Passwort (Test-Stick, kein Daten-PC)
id gpu >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,video,render,adm,systemd-journal gpu
echo 'gpu:gpu' | chpasswd
echo 'gpu ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-gpu; chmod 440 /etc/sudoers.d/90-gpu
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<'EOF'
[Seat:*]
autologin-user=gpu
autologin-user-timeout=0
autologin-session=xfce
user-session=xfce
EOF
systemctl enable lightdm || true
systemctl set-default graphical.target

# Offline-Betrieb: keine automatischen Updates / Hintergrundjobs, die Last erzeugen
systemctl mask apt-daily.timer apt-daily-upgrade.timer man-db.timer \
    e2scrub_all.timer fstrim.timer motd-news.timer 2>/dev/null || true
apt-get -y purge unattended-upgrades ubuntu-advantage-tools ubuntu-pro-client 2>/dev/null || true
# nvidia-persistenced hält den Treiber geladen -> stabilere Messwerte
systemctl enable nvidia-persistenced 2>/dev/null || true

# Journal persistent (für Xid-Auswertung über den Bootvorgang ist volatile ok; klein halten)
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=200M\n' > /etc/systemd/journald.conf.d/size.conf

echo "STAGE1 OK"
