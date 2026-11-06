#!/bin/bash
# update-image.sh – vorhandenes gpucheck.img.xz mit dem Stand dieses Repositorys aktualisieren
# (gpu-check.sh, Anleitung, CLAUDE.md, Build-Skripte, image-stage.sh). Kein Quell-Stick nötig.
#   update-image.sh /pfad/gpucheck.img.xz   (oder ein bereits entpacktes gpucheck.img)
# Platzbedarf: ca. 6 GB. Das alte .xz wird nach dem Entpacken gelöscht und am Ende ersetzt.
set -euo pipefail
IN=$(realpath "${1:?Pfad zu gpucheck.img.xz angeben}")
W=$(cd "$(dirname "$0")" && pwd)
IMG=${IN%.xz}; XZ=$IMG.xz
M=$(dirname "$IMG")/mnt
if [ "$IN" = "$XZ" ]; then
    [ -e "$IMG" ] && { echo "$IMG existiert schon – bitte vorher entfernen"; exit 1; }
    xz -d -k "$XZ"                   # entpackt sparse
    unlink "$XZ"
fi
LOOP=$(losetup -fP --show "$IMG"); udevadm settle
trap 'umount -R "$M" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null' EXIT
mkdir -p "$M"; mount "${LOOP}p3" "$M"
H=$M/home/gpu

# --- Dateien aus dem Repository
install -m755 "$W/../gpu-check.sh"         "$M/opt/gpucheck/gpu-check.sh"
install -m755 "$W/desktop-layout.py"       "$M/opt/gpucheck/desktop-layout.py"
install -m644 "$W/../ANLEITUNG.md"         "$M/opt/gpucheck/README.md"
install -m644 "$W/CLAUDE.md"               "$H/CLAUDE.md"
rm -rf "$M/opt/gpucheck/build"; mkdir -p "$M/opt/gpucheck/build"
cp -r "$W"/. "$M/opt/gpucheck/build/"
cp "$W/../ANLEITUNG.md" "$M/opt/gpucheck/build/README.md"; cp "$W/../gpu-check.sh" "$M/opt/gpucheck/build/"

# --- chroot: image-stage.sh (idempotent)
mount -t proc proc "$M/proc"; mount -t sysfs sysfs "$M/sys"
mount --bind /dev "$M/dev"; mount --make-private "$M/dev"     # NICHT rbind
mount -t devpts devpts "$M/dev/pts" -o newinstance
mount -t tmpfs tmpfs "$M/run"; mkdir -p "$M/run/systemd/resolve"
cp -L /etc/resolv.conf "$M/run/systemd/resolve/stub-resolv.conf"
install -m755 "$W/image-stage.sh" "$M/root/image-stage.sh"
chroot "$M" bash /root/image-stage.sh
unlink "$M/root/image-stage.sh"
umount "$M/dev/pts" "$M/run" "$M/dev" "$M/sys" "$M/proc"
rm -rf "$M"/var/cache/apt/archives/*.deb "$M"/var/cache/apt/*.bin "$M"/root/.cache
find "$M/var/log" -type f -exec truncate -s 0 {} +
# Nameserver des Build-Rechners (resolvconf-Sicherung, alter Stub unter /run des Images)
rm -f "$M/etc/.resolv.conf.systemd-resolved.bak" "$M/run/systemd/resolve/stub-resolv.conf"

# --- Reports-Partition: Anleitung, Skript, Build-Skripte
# komplett leeren (blkdiscard = Nullen, auch gelöschte Reste) und neu formatieren, gleiche UUID wie in fstab
blkdiscard -f "${LOOP}p2"
mkfs.exfat -L GPUREPORTS "${LOOP}p2" >/dev/null; tune.exfat -I 0xFEDBF6CD "${LOOP}p2" >/dev/null
mkdir -p "$M.rep"; mount "${LOOP}p2" "$M.rep"; mkdir -p "$M.rep/build-skripte"
cp "$M/opt/gpucheck/README.md" "$M/opt/gpucheck/gpu-check.sh" "$M.rep/"
( cd "$M/opt/gpucheck/build" && find . -type f ! -path './mock/sys/*' -exec cp --parents {} "$M.rep/build-skripte/" \; )
umount "$M.rep"; rmdir "$M.rep"

# --- freie Blöcke leeren, Journal neu, Kontrolle
fstrim -v "$M"; sync
for i in $(seq 10); do umount "$M" && break; sleep 2; done   # Dateibeobachter (z. B. opencode) halten kurz fest
# Sicherungskopien der reservierten GDT-Blöcke (Resize-Inode 7) nullen: fstrim erreicht sie nicht,
# sie enthielten noch Daten vom Quell-Stick (v1.5 gefunden). Die (IND)-Blöcke selbst bleiben.
debugfs -R "stat <7>" "${LOOP}p3" 2>/dev/null | grep -oE '\([0-9]+\):[0-9]+' | cut -d: -f2 |
    python3 -I -c 'import os,sys
fd=os.open(sys.argv[1],os.O_WRONLY); z=bytes(4096); n=0
for l in sys.stdin: os.pwrite(fd,z,int(l)*4096); n+=1
os.fsync(fd); print("Resize-Inode: %d Blöcke genullt"%n)' "${LOOP}p3"
tune2fs -O ^has_journal "${LOOP}p3" >/dev/null
mount "${LOOP}p3" "$M"; fstrim "$M"; sync; for i in $(seq 10); do umount "$M" && break; sleep 2; done
tune2fs -O has_journal "${LOOP}p3" >/dev/null
e2fsck -fy "${LOOP}p3"
losetup -d "$LOOP"; trap - EXIT; rmdir "$M"

PAT='sk-an[t]-'   # [t]: Muster findet sich nicht selbst in diesem Skript
[ -n "${GPUCHECK_SCAN:-}" ] && PAT="$PAT|$GPUCHECK_SCAN"
if LC_ALL=C command grep -a -q -E "$PAT" "$IMG"; then
    echo "ABBRUCH: persönliche Daten im Image gefunden:"; LC_ALL=C command grep -a -o -E "$PAT" "$IMG" | sort | uniq -c; exit 1
fi
echo "Rohsuche: keine Treffer"
xz -T2 -6 -f "$IMG"; xz -t "$XZ"   # -T2: wenig RAM (je Thread ~100 MB)
( cd "$(dirname "$XZ")" && sha256sum "$(basename "$XZ")" > "$(basename "$XZ").sha256" && cat "$(basename "$XZ").sha256" )
[ -n "${SUDO_UID:-}" ] && chown "$SUDO_UID:$SUDO_GID" "$XZ" "$XZ.sha256"
echo "FERTIG: $XZ"
