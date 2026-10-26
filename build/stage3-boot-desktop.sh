#!/bin/bash
# Stage 3 (im chroot): fstab, GRUB (Secure-Boot-fähig, Removable-Pfad), Desktop-Einrichtung.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
U=gpu; H=/home/$U
ROOT_UUID=$1; EFI_UUID=$2; REP_UUID=$3

# ---------------------------------------------------------------- fstab
cat > /etc/fstab <<EOF
# gpucheck USB-Stick
UUID=$ROOT_UUID  /             ext4   noatime,commit=60,errors=remount-ro  0 1
UUID=$EFI_UUID   /boot/efi     vfat   umask=0077,nofail                    0 2
UUID=$REP_UUID   /mnt/reports  exfat  uid=1000,gid=1000,umask=0002,nofail,x-systemd.device-timeout=5s  0 0
tmpfs            /tmp          tmpfs  defaults,size=25%                     0 0
EOF
mkdir -p /mnt/reports

# ---------------------------------------------------------------- GRUB
cat > /etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="GPU-Check"
# iomem=relaxed: VRAM-Temperatur (gddr6) – wirkt nur, wenn Secure Boot AUS ist.
GRUB_CMDLINE_LINUX_DEFAULT="quiet iomem=relaxed nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
GRUB_DISABLE_RECOVERY=true
GRUB_TERMINAL=console
EOF
cat > /etc/grub.d/40_custom <<'EOF'
#!/bin/sh
exec tail -n +3 $0
menuentry "GPU-Check - Textmodus (ohne Desktop, falls Grafik nicht startet)" {
    search --no-floppy --label gpucheck-root --set=root
    linux /boot/vmlinuz root=LABEL=gpucheck-root ro iomem=relaxed systemd.unit=multi-user.target
    initrd /boot/initrd.img
}
menuentry "GPU-Check - Notfall-Grafik (nomodeset, NVIDIA-Treiber aus)" {
    search --no-floppy --label gpucheck-root --set=root
    linux /boot/vmlinuz root=LABEL=gpucheck-root ro nomodeset modprobe.blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm
    initrd /boot/initrd.img
}
EOF
chmod 755 /etc/grub.d/40_custom

# Signierte Kette in zwei Pfade:
#  EFI/ubuntu/  – der signierte GRUB sucht seine grub.cfg fest unter /EFI/ubuntu
#  EFI/BOOT/    – Fallback-Pfad (BOOTX64.EFI = shim), bootet ohne NVRAM-Eintrag
# --no-nvram: NIE Boot-Einträge im (fremden/eigenen) Rechner anlegen.
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --uefi-secure-boot --no-nvram
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable --uefi-secure-boot --no-nvram
# shim-Fallback (fbx64.efi) würde auf dem Testrechner Boot-Einträge anlegen -> entfernen
[ -f /boot/efi/EFI/BOOT/fbx64.efi ] && unlink /boot/efi/EFI/BOOT/fbx64.efi
update-initramfs -u -k all
update-grub
# Signierter GRUB 2.14 bekommt beim Start über EFI/BOOT kein $cmdpath und sucht dann
# (ESP)/boot/grub/grub.cfg -> gleiche Weiterleitung auch dort ablegen (im VM-Test gefunden).
mkdir -p /boot/efi/boot/grub
cp /boot/efi/EFI/ubuntu/grub.cfg /boot/efi/boot/grub/grub.cfg

# ---------------------------------------------------------------- Desktop
getent group autologin >/dev/null || groupadd -r autologin
usermod -aG autologin $U

# feste (englische) XDG-Ordnernamen, damit die Icons sicher auf dem Desktop liegen
sed -i 's/^enabled=.*/enabled=False/' /etc/xdg/user-dirs.conf 2>/dev/null || true
install -d -o $U -g $U $H/Desktop $H/.config $H/.config/autostart \
    $H/.config/xfce4/xfconf/xfce-perchannel-xml
cat > $H/.config/user-dirs.dirs <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME"
XDG_DOCUMENTS_DIR="$HOME"
EOF
# Panel ohne Rückfrage "Standard/leeres Panel"
cp /etc/xdg/xfce4/panel/default.xml $H/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
# Bildschirm nicht abschalten/sperren
cat > $H/.config/autostart/no-blank.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Kein Bildschirmschoner
Exec=sh -c "xset s off; xset s noblank; xset -dpms"
X-GNOME-Autostart-enabled=true
EOF
# Desktop-Launcher als vertrauenswürdig markieren (xfdesktop prüft Checksumme; geht nur in laufender Sitzung)
cat > $H/.config/autostart/trust-launchers.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Desktop-Starter freigeben
Exec=sh -c 'sleep 2; for f in "$HOME"/Desktop/*.desktop; do gio set -t string "$f" metadata::xfce-exe-checksum "$(sha256sum "$f" | cut -d" " -f1)"; done; xfdesktop --reload'
X-GNOME-Autostart-enabled=true
EOF

mk_launcher() {  # datei name icon exec terminal
    cat > "$H/Desktop/$1.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$2
Icon=$3
Exec=$4
Terminal=false
EOF
    chmod 755 "$H/Desktop/$1.desktop"
}
mk_launcher 1-gpu-schnelltest "GPU-Schnelltest (~5 Min.)" media-playback-start-symbolic \
    'xfce4-terminal --maximize --hold --title="GPU-Check Schnelltest" -x /opt/gpucheck/gpu-check.sh --quick'
mk_launcher 2-gpu-volltest "GPU-Volltest (~20 Min.)" applications-system-symbolic \
    'xfce4-terminal --maximize --hold --title="GPU-Check Volltest" -x /opt/gpucheck/gpu-check.sh --full'
mk_launcher 3-reports "Reports öffnen" folder-documents 'thunar /mnt/reports'
mk_launcher 4-nvtop "nvtop (Live-Monitor)" nvtop 'xfce4-terminal --title=nvtop -x nvtop'
mk_launcher 5-readme "Anleitung (README)" help-browser-symbolic 'mousepad /opt/gpucheck/README.md'
mk_launcher 6-terminal "Terminal" org.xfce.terminal 'xfce4-terminal'
chown -R $U:$U $H

# Werkzeuge in den PATH
ln -sf /opt/gpucheck/gpu-check.sh /usr/local/bin/gpu-check
ln -sf /opt/gpucheck/bin/memtest_vulkan /usr/local/bin/memtest_vulkan
ln -sf /opt/gpucheck/bin/gddr6 /usr/local/bin/gddr6
printf '#!/bin/sh\n# gpu_burn erwartet compare.ptx im Arbeitsverzeichnis\ncd /opt/gpucheck/gpu-burn && exec ./gpu_burn "$@"\n' > /usr/local/bin/gpu_burn
chmod 755 /usr/local/bin/gpu_burn

echo "STAGE3 OK"
