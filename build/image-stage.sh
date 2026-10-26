#!/bin/bash
# image-stage.sh (im chroot des Images): Wachsen beim 1. Start, Claude-Code-Installer, Versionsstand.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
U=gpu; H=/home/$U

apt-get update
apt-get -y install cloud-guest-utils gdisk        # growpart, sgdisk

# --- Root-Partition beim ersten Start auf den ganzen Stick vergrößern
cat > /usr/local/sbin/gpucheck-grow-root <<'EOF'
#!/bin/sh
# Einmalig nach dem Aufspielen: Backup-GPT ans Stick-Ende, Partition 3 + ext4 vergrößern.
ROOT=$(findmnt -no SOURCE /)
DISK=/dev/$(lsblk -no PKNAME "$ROOT")
PART=$(cat "/sys/class/block/$(basename "$ROOT")/partition")
sgdisk -e "$DISK"
growpart "$DISK" "$PART"; rc=$?           # rc 1 = war schon maximal
[ $rc -le 1 ] && resize2fs "$ROOT" && rm -f /etc/gpucheck-grow-root
EOF
chmod 755 /usr/local/sbin/gpucheck-grow-root
cat > /etc/systemd/system/gpucheck-grow-root.service <<'EOF'
[Unit]
Description=GPU-Check: Root-Partition auf Stick-Größe erweitern (einmalig)
ConditionPathExists=/etc/gpucheck-grow-root
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/gpucheck-grow-root
[Install]
WantedBy=multi-user.target
EOF
touch /etc/gpucheck-grow-root
systemctl enable gpucheck-grow-root.service

# --- Claude Code: nicht im Image (proprietär), Installation beim ersten Aufruf
unlink /usr/local/bin/claude 2>/dev/null || true
cat > /usr/local/bin/claude <<'EOF'
#!/bin/sh
# Claude Code ist nicht im Image enthalten. Beim ersten Aufruf wird es installiert (Internet nötig).
C="$HOME/.local/bin/claude"
if [ ! -x "$C" ]; then
    echo "Claude Code wird installiert (braucht Internet) ..."
    if ! curl -fsSL https://claude.ai/install.sh | bash; then
        echo "Installation fehlgeschlagen. Internetverbindung prüfen (Netzwerk-Symbol oben rechts)."
        echo "Enter zum Schließen"; read -r _; exit 1
    fi
fi
exec "$C" "$@"
EOF
chmod 755 /usr/local/bin/claude

# --- gddr6 (VRAM-Temperatur): Projekt ohne Lizenz -> nicht weitergeben, per Icon nachrüstbar
rm -f /opt/gpucheck/bin/gddr6 /usr/local/bin/gddr6 /opt/gpucheck/src/src-586c77ac*.tar.gz
cat > $H/Desktop/10-gddr6.desktop <<'EOF2'
[Desktop Entry]
Version=1.0
Type=Application
Name=VRAM-Temperatur nachrüsten
Icon=folder-download-symbolic
Exec=xfce4-terminal --hold --title="VRAM-Temperatur nachrüsten" -x /opt/gpucheck/gddr6-nachruesten.sh
Terminal=false
EOF2
chmod 755 $H/Desktop/10-gddr6.desktop /opt/gpucheck/gddr6-nachruesten.sh
bash -n /opt/gpucheck/gpu-check.sh
find /usr/share/icons -name "folder-download-symbolic*" | grep -q . || echo "WARNUNG: Icon folder-download-symbolic fehlt"
chown -R $U:$U $H
apt-get clean
echo "IMAGE-STAGE OK"
