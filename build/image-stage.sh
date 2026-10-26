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

# --- gddr6: Projekt ohne Lizenz -> nicht weitergeben (ersetzt durch gputemps)
rm -f /opt/gpucheck/bin/gddr6 /usr/local/bin/gddr6 /opt/gpucheck/src/src-586c77ac*.tar.gz \
      /opt/gpucheck/gddr6-nachruesten.sh $H/Desktop/10-gddr6.desktop

# --- gputemps (ThomasBaruzier/gddr6-core-junction-vram-temps, Apache-2.0):
#     VRAM- und Hotspot-Temperatur über /dev/mem (iomem=relaxed, Secure Boot aus).
#     NVML-Header nur aus dem Paket entpackt (nicht installiert), gelinkt gegen den Treiber.
GT_SHA=6d8c5ecf633a8658d205fb2c24531bf87164912f
GT_SUM=cd0ecedef97170869a59d61b4a6dbb8e6f83ba18c844e5f465bd41a025292d12
GT_URL=https://github.com/ThomasBaruzier/gddr6-core-junction-vram-temps/archive/$GT_SHA.tar.gz
T=$(mktemp -d)
dpkg-query -W -f '${Package}\n' | sort > $T/before
apt-get install -y --no-install-recommends gcc make libc6-dev libpci-dev
( cd $T && apt-get download libnvidia-ml-dev && dpkg -x libnvidia-ml-dev_*.deb nvml )
curl -fsSL "$GT_URL" -o $T/gputemps.tar.gz
echo "$GT_SUM  $T/gputemps.tar.gz" | sha256sum -c
mkdir $T/src; tar -xzf $T/gputemps.tar.gz -C $T/src --strip-components=1
make -C $T/src NVML_HEADER="$(find $T/nvml -name nvml.h | head -1)"
install -m755 $T/src/gputemps /opt/gpucheck/bin/gputemps
ln -sf /opt/gpucheck/bin/gputemps /usr/local/bin/gputemps
install -Dm644 $T/src/LICENSE /usr/share/doc/gputemps/LICENSE
cp $T/gputemps.tar.gz /opt/gpucheck/src/gputemps-$GT_SHA.tar.gz
# nur die eben installierten Build-Pakete wieder entfernen
dpkg-query -W -f '${Package}\n' | sort > $T/after
comm -13 $T/before $T/after | xargs -r apt-get purge -y
rm -rf $T
ldd /opt/gpucheck/bin/gputemps | grep -E 'nvidia-ml|pci'

# --- Desktop: Schnell-/Volltest oben links, Rest rechts (siehe desktop-layout.py)
X=$H/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
cat > $X <<'EOF2'
<?xml version="1.1" encoding="UTF-8"?>

<channel name="xfce4-desktop" version="1.0">
  <property name="last-settings-migration-version" type="uint" value="1"/>
  <property name="desktop-icons" type="empty">
    <property name="gravity" type="int" value="2"/>
  </property>
</channel>
EOF2
rm -f $H/.config/autostart/trust-launchers.desktop $H/.config/xfce4/desktop/icons.screen0.yaml
printf '[Desktop Entry]\nType=Application\nName=GPU-Check Desktop anordnen\nExec=/opt/gpucheck/desktop-layout.py\nX-GNOME-Autostart-enabled=true\n' \
    > $H/.config/autostart/gpucheck-layout.desktop
cat > /etc/tmpfiles.d/gpucheck-desktop.conf <<'EOF2'
# GPU-Check: Icon-Positionen bei jedem Start verwerfen – xfdesktop ordnet für den aktuellen
# Bildschirm neu an, /opt/gpucheck/desktop-layout.py setzt Schnell-/Volltest nach links.
r /home/gpu/.config/xfce4/desktop/icons.screen0.yaml
EOF2
chmod 755 /opt/gpucheck/desktop-layout.py
bash -n /opt/gpucheck/gpu-check.sh
chown -R $U:$U $H
apt-get clean
echo "IMAGE-STAGE OK"
