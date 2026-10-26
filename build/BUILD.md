# Wie das Image entsteht

Für die normale Nutzung nicht nötig – einfach das fertige Image aufspielen (siehe `../ANLEITUNG.md`).

Gebaut wurde auf einem Debian-13-Host (LMDE 7) direkt auf einen USB-Stick; daraus wird
mit `make-image.sh` das bereinigte Image. Schritt 0 wurde **von Hand** ausgeführt, die Befehle
unten sind die Zusammenfassung – kein getestetes Skript.

## 0. Stick vorbereiten (von Hand, als root)

```sh
# Stick: GPT, ESP 512 MiB, exFAT 2 GiB (Reports), Rest ext4
sgdisk -Z -n1:0:+512M -t1:EF00 -c1:EFI -n2:0:+2G -t2:0700 -c2:GPUREPORTS \
       -n3:0:0 -t3:8304 -c3:gpucheck-root /dev/sdX
mkfs.vfat -F32 -n GPUCHK-EFI /dev/sdX1
mkfs.exfat -L GPUREPORTS /dev/sdX2
mkfs.ext4 -L gpucheck-root /dev/sdX3

mount /dev/sdX3 /mnt/t; mkdir -p /mnt/t/boot/efi; mount /dev/sdX1 /mnt/t/boot/efi
# Ubuntu 26.04 "resolute"; Debians debootstrap kennt resolute noch nicht -> Skript von questing
# Archivschlüssel: F6ECB3762474EDA9D21B7022871920D1991BC93C (vorher prüfen)
debootstrap --arch=amd64 --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    resolute /mnt/t http://archive.ubuntu.com/ubuntu /usr/share/debootstrap/scripts/questing

# chroot-Umgebung: /dev NICHT rekursiv binden (rbind + umount -R hängt sonst /dev/pts des Hosts aus)
mount -t proc proc /mnt/t/proc; mount -t sysfs sysfs /mnt/t/sys
mount --bind /dev /mnt/t/dev; mount --make-private /mnt/t/dev
mount -t devpts devpts /mnt/t/dev/pts -o newinstance
mount -t tmpfs tmpfs /mnt/t/run; mkdir -p /mnt/t/run/systemd/resolve
cp -L /etc/resolv.conf /mnt/t/run/systemd/resolve/stub-resolv.conf
```

Downloads nach `/mnt/t/root/build/dl/` (Prüfsummen selbst kontrollieren):

| Datei | Quelle |
|---|---|
| `memtest/memtest_vulkan-v0.5.0_DesktopLinux_X86_64.tar.xz` | GitHub-Release GpuZelenograd/memtest_vulkan v0.5.0 |
| `gpuburn/src-0d19c94….tar.gz` | wilicc/gpu-burn, Commit 0d19c94 |
| `gddr6/src-586c77a….tar.gz` | olealgoritme/gddr6, Commit 586c77a (wird für das öffentliche Image wieder entfernt) |
| `cuda/cuda-keyring_1.1-1_all.deb` | developer.download.nvidia.com, Repo `ubuntu2604` |

## 1.–4. Stufen im chroot

```sh
chroot /mnt/t bash /root/build/stage1-system.sh      # Basissystem, Kernel, NVIDIA 595 open, XFCE, Autologin
chroot /mnt/t bash /root/build/stage2-tools.sh       # memtest_vulkan, gddr6, gpu-burn (CUDA danach wieder entfernt)
chroot /mnt/t bash /root/build/stage3-boot-desktop.sh <ROOT-UUID> <EFI-UUID> <REPORTS-UUID>
chroot /mnt/t bash /root/build/stage4-extras.sh      # Chromium (xtradeb), WLAN, Claude Code, opencode
chroot /mnt/t bash /root/build/stage4b-desktop.sh    # LAN über NetworkManager, weitere Icons
```

Danach `gpu-check.sh` nach `/opt/gpucheck/`, `../ANLEITUNG.md` als `/opt/gpucheck/README.md`.

## 5. Image erzeugen

```sh
STICK_SERIAL=<Seriennummer> GPUCHECK_SCAN='eigene@mail|eigener-name' ./make-image.sh /dev/sdX
```

Liest den Stick **nur**, bereinigt eine Kopie (Logins, Verläufe, Logs, WLAN, Browserprofil,
Spuren des Test-PCs), entfernt gddr6 und Claude Code, verkleinert auf 7 GiB (wächst beim
ersten Start), leert freie Blöcke und das ext4-Journal, sucht roh nach persönlichen Daten und
erzeugt `gpucheck.img.xz` + `.sha256`.

Ein vorhandenes Image auf den Stand des Repositorys bringen (ohne Stick):

```sh
GPUCHECK_SCAN='eigene@mail' ./update-image.sh /pfad/gpucheck.img.xz
```

## Testen ohne Grafikkarte

`mock/` simuliert eine RTX 3090. Beispiel (als root, im Verzeichnis `build/mock`):

```sh
PATH=$PWD/bin:$PWD/gpuburn:$PATH MEMTEST_BIN=$PWD/bin/mock-memtest GPUBURN_DIR=$PWD/gpuburn \
GDDR6_BIN=$PWD/bin/gddr6 REPORT_ROOT=/tmp/reports NV_ICD=/dev/null \
PCI_SYSFS=$(./mk-sys.sh /tmp/gpucheck-mock-sys) \
MOCK_SCENARIO=bad ../../gpu-check.sh --quick --idle 3 --memtest 6 --burn 15 --no-gl --no-ask
```

`MOCK_SCENARIO=good|bad`, `MOCK_OLDFIELDS=1` simuliert ältere Treiber-Feldnamen. `mk-sys.sh` erzeugt
das simulierte PCI-sysfs (nicht im Repository, weil Dateinamen mit `:` unter Windows nicht gehen).
Erwartet: `good` → GESAMT PASS, `bad` → GESAMT FAIL mit VRAM-, Rechen-, Temperatur-, Throttle-,
Leistungs-, Takt- und Xid-Fehlern.

`vmtest.sh`/`vmtype.py`: Stick schreibgeschützt in QEMU/OVMF booten (mit/ohne Secure Boot).
