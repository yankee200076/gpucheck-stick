#!/bin/bash
# make-image.sh – erzeugt aus dem GPU-Check-Stick ein weitergebbares Image (gpucheck.img.xz).
# Der Stick wird NUR GELESEN. Bereinigt wird die Kopie in der Image-Datei.
#   STICK_SERIAL=<Seriennummer> make-image.sh /dev/sdX
#   (Stick mit Labels GPUCHK-EFI / GPUREPORTS / gpucheck-root; Seriennummer: lsblk -o NAME,SERIAL)
set -euo pipefail
SRC=${1:?Stick-Gerät angeben}
W=$(cd "$(dirname "$0")" && pwd)
IMG=$W/gpucheck.img
M=$W/mnt
ROOT_GIB=7                       # Größe der Root-Partition im Image (wächst beim 1. Start)
STICK_SERIAL=${STICK_SERIAL:?Seriennummer des Quell-Sticks angeben (Schutz vor falschem Gerät)}

[ "$(lsblk -dno SERIAL "$SRC")" = "$STICK_SERIAL" ] || { echo "falscher Stick"; exit 1; }
for p in 1 2 3; do findmnt -rn "${SRC}$p" >/dev/null && { echo "${SRC}$p ist eingehängt"; exit 1; }; done

# ---------------------------------------------------------------- 1. Rohkopie (sparse)
[ -e "$IMG" ] && unlink "$IMG"
truncate -s "$(blockdev --getsize64 "$SRC")" "$IMG"
sgdisk --backup="$W/gpt.bak" "$SRC" >/dev/null
sgdisk --load-backup="$W/gpt.bak" "$IMG" >/dev/null
LOOP=$(losetup -fP --show "$IMG"); echo "Image an $LOOP"
trap 'umount -R "$M" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null' EXIT
udevadm settle
dd if="${SRC}1" of="${LOOP}p1" bs=4M conv=sparse status=none          # ESP: nur Bootdateien
e2image -ra -p "${SRC}3" "${LOOP}p3"                                    # Root: nur belegte Blöcke
mkfs.exfat -L GPUREPORTS "${LOOP}p2" >/dev/null                          # Reports: leer, ohne deine Daten
tune.exfat -I 0xFEDBF6CD "${LOOP}p2" >/dev/null                          # gleiche UUID wie in fstab

# ---------------------------------------------------------------- 2. Root bereinigen
mkdir -p "$M"
mount "${LOOP}p3" "$M"
H=$M/home/gpu
# Claude Code: Login, Konto, Verlauf, Programm (proprietär -> nicht im Image, Installation beim 1. Aufruf)
rm -rf "$M/root/.claude" "$M/root/.claude.json" "$H/.claude" "$H/.claude.json" \
       "$H/.local/share/claude" "$H/.local/bin/claude" "$M/root/.local/share/applications/claude-code-url-handler.desktop"
# opencode: Login/Sitzungen/Logs (Programm bleibt, MIT-Lizenz)
rm -rf "$H/.local/share/opencode" "$H/.local/state/opencode" "$H/.config/opencode" "$H/.cache/opencode"
# Browser, Schlüsselbund, Verläufe, Sitzungsreste
rm -rf "$H/.config/chromium" "$M/root/.config/chromium" "$H/.local/share/keyrings" "$H/.gnupg" \
       "$H/.cache" "$M/root/.cache" "$M/root/.config" "$M/root/.local" "$M/root/.nv" \
       "$H/.config/pulse" "$H/.config/dconf" "$H/.config/Thunar" "$H/.local/share/gvfs-metadata" \
       "$H/.local/share/Mousepad" "$H/.local/share/pki" "$H/.local/share/recently-used.xbel" \
       "$H/.local/state" "$H/.bash_history" "$M/root/.bash_history" "$H/.ICEauthority" \
       "$H/.Xauthority" "$H"/.xsession-errors* "$H/.nv"
# Netzwerk: WLAN-Passwörter, Leases, gesehene Netze
find "$M/etc/NetworkManager/system-connections" -mindepth 1 -delete
rm -rf "$M"/var/lib/NetworkManager/*
# Logs, Spuren des Test-PCs (Seriennummern fremder Platten in smartmontools!)
find "$M/var/log" -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.old' \) -delete
find "$M/var/log" -type f -exec truncate -s 0 {} +
rm -rf "$M"/var/log/journal/* "$M"/var/lib/smartmontools/* "$M"/var/lib/chrony/* \
       "$M"/var/lib/systemd/random-seed "$M"/var/lib/systemd/coredump/* "$M"/var/crash/* \
       "$M"/var/tmp/* "$M"/var/lib/sudo/* "$M"/var/cache/apt/*.bin "$M"/var/lib/lightdm/.cache \
       "$M/opt/gpucheck/gpu-check.sh.bak"
: > "$M/etc/machine-id"                      # leer -> neue ID beim ersten Start
# aktuelle Skripte und Doku aus dem Repository
install -m755 "$W/../gpu-check.sh" "$M/opt/gpucheck/gpu-check.sh"
install -m755 "$W/gddr6-nachruesten.sh" "$M/opt/gpucheck/gddr6-nachruesten.sh"
install -m644 "$W/../ANLEITUNG.md" "$M/opt/gpucheck/README.md"
install -m644 "$W/CLAUDE.md" "$H/CLAUDE.md"; install -m644 "$W/CLAUDE.md" "$M/opt/gpucheck/build/CLAUDE.md"
install -m644 "$W/../ANLEITUNG.md" "$M/opt/gpucheck/build/README.md"
cp "$M/opt/gpucheck/gpu-check.sh" "$M/opt/gpucheck/build/gpu-check.sh"
grub-editenv "$M/boot/grub/grubenv" create   # recordfail usw. zurücksetzen

# ---------------------------------------------------------------- 3. Image-spezifische Änderungen (chroot)
mount -t proc proc "$M/proc"; mount -t sysfs sysfs "$M/sys"
mount --bind /dev "$M/dev"; mount --make-private "$M/dev"     # NICHT rbind: kein Aushängen zum Host
mount -t devpts devpts "$M/dev/pts" -o newinstance
mount -t tmpfs tmpfs "$M/run"; mkdir -p "$M/run/systemd/resolve"
cp -L /etc/resolv.conf "$M/run/systemd/resolve/stub-resolv.conf"
install -m755 "$W/image-stage.sh" "$M/root/image-stage.sh"
chroot "$M" bash /root/image-stage.sh
unlink "$M/root/image-stage.sh"
rm -rf "$M"/var/cache/apt/archives/*.deb "$M"/var/cache/apt/*.bin "$M"/var/log/apt/* "$M"/root/.cache
find "$M/var/log" -type f -exec truncate -s 0 {} +
umount "$M/dev/pts" "$M/run" "$M/dev" "$M/sys" "$M/proc"

# Reports-Partition: Anleitung + Skript
mkdir -p "$W/rep"; mount "${LOOP}p2" "$W/rep"
cp "$M/opt/gpucheck/README.md" "$M/opt/gpucheck/gpu-check.sh" "$W/rep/"
mkdir -p "$W/rep/build-skripte"
( cd "$M/opt/gpucheck/build" && find . -type f ! -path './mock/sys/*' -exec cp --parents {} "$W/rep/build-skripte/" \; )
umount "$W/rep"

# ---------------------------------------------------------------- 4. freie Blöcke leeren, verkleinern
fstrim -v "$M"                               # Loop-Device: Löcher in die Datei stanzen = gelöschte Daten weg
umount "$M"
e2fsck -fy "${LOOP}p3"
resize2fs "${LOOP}p3" ${ROOT_GIB}G
# ext4-Journal enthält noch Metadaten gelöschter Dateien (z. B. Dateinamen mit Plattenmodellen
# des Test-PCs) -> Journal entfernen, freie Blöcke erneut leeren, Journal neu (genullt) anlegen
tune2fs -O ^has_journal "${LOOP}p3" >/dev/null
mount "${LOOP}p3" "$M"; fstrim -v "$M"; umount "$M"
tune2fs -O has_journal "${LOOP}p3" >/dev/null
e2fsck -fn "${LOOP}p3"
losetup -d "$LOOP"; trap - EXIT
# Partition 3 verkürzen (gleicher Start, gleiche PARTUUID), Datei abschneiden, Backup-GPT ans Ende
P3_START=$(sgdisk -i 3 "$IMG" | awk '/First sector/{print $3}')
P3_GUID=$(sgdisk -i 3 "$IMG" | awk '/unique GUID/{print $4}')
P3_END=$((P3_START + ROOT_GIB * 1024 * 1024 * 2 - 1))
sgdisk -d 3 -n 3:"$P3_START":"$P3_END" -t 3:8304 -c 3:gpucheck-root -u 3:"$P3_GUID" "$IMG" >/dev/null
truncate -s $(( (P3_END + 1 + 2048) * 512 )) "$IMG"
sgdisk -e "$IMG" >/dev/null
sgdisk -v "$IMG"
sgdisk -p "$IMG"
echo "IMAGE OK: $IMG ($(du -h --apparent-size "$IMG" | cut -f1) logisch, $(du -h "$IMG" | cut -f1) belegt)"

# ---------------------------------------------------------------- 5. Kontrolle, komprimieren
# Rohsuche über das ganze Image (auch freie Bereiche) nach Zugangsdaten / Spuren des Stick-Besitzers.
# Eigene Suchbegriffe (E-Mail, Benutzername, Board/Platten des Test-PCs) per GPUCHECK_SCAN="a|b" übergeben.
PAT="sk-an[t]-|$STICK_SERIAL"   # [t]: Muster findet sich nicht selbst
[ -n "${GPUCHECK_SCAN:-}" ] && PAT="$PAT|$GPUCHECK_SCAN"
if LC_ALL=C command grep -a -q -E "$PAT" "$IMG"; then
    echo "ABBRUCH: persönliche Daten im Image gefunden:"; LC_ALL=C command grep -a -o -E "$PAT" "$IMG" | sort | uniq -c
    exit 1
fi
echo "Rohsuche: keine Treffer"
xz -T0 -6 -f "$IMG"                          # ersetzt gpucheck.img durch gpucheck.img.xz
xz -t "$IMG.xz"
( cd "$W" && sha256sum "$(basename "$IMG").xz" > "$(basename "$IMG").xz.sha256" && cat "$(basename "$IMG").xz.sha256" )
[ -n "${SUDO_UID:-}" ] && chown "$SUDO_UID:$SUDO_GID" "$IMG.xz" "$IMG.xz.sha256"
rmdir "$M" "$W/rep" 2>/dev/null; unlink "$W/gpt.bak"
echo "FERTIG: $IMG.xz"
