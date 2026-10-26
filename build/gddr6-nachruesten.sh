#!/bin/bash
# gddr6-nachruesten.sh – VRAM-Temperatur-Tool (olealgoritme/gddr6) auf dem Stick bauen.
#
# Das Projekt hat keine Lizenz und darf deshalb nicht im weitergegebenen Image liegen.
# Dieses Skript lädt den Quellcode direkt vom Original-Projekt und baut ihn lokal.
# Braucht einmal Internet (ca. 250 MB Build-Werkzeuge, etwa 1–2 Minuten).
# Danach misst gpu-check die VRAM-Temperatur (nur mit Secure Boot AUS).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

COMMIT=586c77ac61ae06a2992bc8e86b9def95c8151e96     # auf RTX 3090 (Ampere) getestet
URL=https://github.com/olealgoritme/gddr6/archive/$COMMIT.tar.gz
DEST=/opt/gpucheck/bin/gddr6

if [ -x "$DEST" ]; then
    echo "gddr6 ist bereits installiert ($DEST)."
    exit 0
fi
if ! curl -fsI --max-time 10 https://github.com >/dev/null; then
    echo "Keine Internetverbindung. Bitte LAN-Kabel einstecken oder WLAN wählen"
    echo "(Netzwerk-Symbol oben rechts) und das Icon erneut starten."
    exit 1
fi

echo "== Build-Werkzeuge installieren"
apt-get update
apt-get install -y --no-install-recommends build-essential cmake pkg-config libpci-dev

echo "== gddr6 laden (Commit ${COMMIT:0:7}) und bauen"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
curl -fL "$URL" | tar -xz -C "$T" --strip-components=1
cmake -S "$T" -B "$T/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$T/build" -j"$(nproc)"
install -m755 "$(find "$T/build" -type f -name gddr6 -perm -u+x | head -1)" "$DEST"
ln -sf "$DEST" /usr/local/bin/gddr6
apt-get clean

echo
echo "Fertig: VRAM-Temperatur-Tool installiert."
if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    echo "Hinweis: Secure Boot ist AN. Die VRAM-Temperatur ist erst lesbar, wenn Secure Boot"
    echo "im BIOS ausgeschaltet ist (Kernel-Lockdown sperrt sonst /dev/mem)."
fi
