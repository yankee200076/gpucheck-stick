# GPU-Check-Stick – Kontext für Claude Code

Du läufst auf einem bootfähigen USB-Stick (aus dem Image gpucheck.img.xz), mit dem gebrauchte
NVIDIA-Grafikkarten (Ampere/Ada/Blackwell) vor dem Kauf geprüft werden. Antworte auf Deutsch.
Benutzer `gpu` (Passwort `gpu`), `sudo` ohne Passwort.

## System
- Ubuntu 26.04 LTS „resolute“, Kernel 7.0.0-38-generic, XFCE + LightDM-Autologin
- NVIDIA 595.99.02 open: `linux-modules-nvidia-595-open-generic` (von Canonical signiert, kein DKMS)
  + `nvidia-driver-595-open`. Kein nouveau.
- Boot: shim + signierter GRUB in `EFI/BOOT/BOOTX64.EFI` und `EFI/ubuntu/`; Weiterleitung
  zusätzlich in `ESP:/boot/grub/grub.cfg` (signierter GRUB 2.14 sucht dort ohne `$cmdpath`).
  Es werden **keine** NVRAM-Einträge angelegt (`--no-nvram`), `fbx64.efi` entfernt.
- Kernel-Parameter: `quiet iomem=relaxed nvidia-drm.modeset=1`
  (`iomem=relaxed` für gputemps/VRAM-/Hotspot-Temperatur, wirkt nur mit Secure Boot AUS – Lockdown sperrt /dev/mem).
- Partitionen: sda1 ESP „GPUCHK-EFI“ → /boot/efi · sda2 exFAT „GPUREPORTS“ → /mnt/reports ·
  sda3 ext4 „gpucheck-root“ → /  (Gerätename kann anders sein, Labels nutzen). Root wächst beim
  ersten Start einmalig auf Stick-Größe (`gpucheck-grow-root.service`, Flag `/etc/gpucheck-grow-root`).
- Netzwerk: NetworkManager (nm-applet im Panel), WLAN über wpasupplicant.

## Werkzeuge
- `/opt/gpucheck/gpu-check.sh` (= `gpu-check`): Haupttest, `--quick` ~5 Min., `--full` ~20 Min.,
  `--help`. Grenzwerte in Funktion `set_limits`. Reports: `/mnt/reports/<Zeitstempel>_<Karte>/`
  (report.txt, summary.txt, *.csv, kernel.log, nvidia-smi-q.txt).
- `/opt/gpucheck/bin/memtest_vulkan` v0.5.0 (Argument `1` = nicht-interaktiv, Ende per SIGTERM,
  Exit = 0x40 | Status-Bits)
- `/opt/gpucheck/gpu-burn/` (gpu_burn + compare.fatbin, CUDA-13-Libs in `lib/`, Wrapper `/usr/local/bin/gpu_burn`)
- `/opt/gpucheck/bin/gputemps` (Apache-2.0, Commit 6d8c5ec): `gputemps --json --device N` liefert je Sekunde
  core/junction(Hotspot)/vram; braucht root, iomem=relaxed, Secure Boot aus. Ersetzt gddr6 (ohne Lizenz).
- Desktop: `/opt/gpucheck/desktop-layout.py` (Autostart) setzt Schnell-/Volltest oben links, Rest rechts;
  xfdesktop-Gravity 2 (oben rechts), Positionsdatei wird per `/etc/tmpfiles.d/gpucheck-desktop.conf` bei jedem Boot gelöscht.
- vkmark (`--winsys xcb`), glmark2, nvtop, nvidia-settings, stress-ng, chromium, opencode
- `claude` = `/usr/local/bin/claude`: Wrapper, installiert Claude Code beim ersten Aufruf nach `~/.local/bin`
- Build-Skripte des Sticks: `/opt/gpucheck/build/` (stage1–4b, Mock-Testumgebung in `mock/`)

## Bekannte Punkte / Historie
- v1.0: „nvidia-smi sieht die Karte nicht“ trotz laufendem Treiber – Ursache `nvidia-smi -i 0 -L`.
  Seit v1.1 Erkennung über `--query-gpu=index,pci.bus_id,name` mit Wiederholung.
- v1.2 (nach Test auf echter RTX 3090, Treiber 595):
  - `clocks.default_applications.graphics` liefert „deprecated“ -> Referenz-Basistakt-Tabelle `ref_base_clk`
  - Lüfter-RPM nur mit `nvidia-settings -q '[fan]/GPUCurrentFanSpeedRPM'`
  - vkmark 2025.01 beendet sich auf SIGTERM mit Exit 0 (ältere 143) -> beides OK, wenn Laufzeit erreicht
  - Durchschnittswerte nur aus Messpunkten mit ≥ 50 % Auslastung (`load_active.csv`)
  - Report per `cp` statt `mv` auf exFAT (keine Eigentümer-Warnung)
- v1.3: Hinweis im Report, wenn gddr6 fehlt (öffentliches Image ohne gddr6, Nachrüsten per Icon).
- v1.4: gputemps statt gddr6, neue Prüfpunkte Hotspot-Temperatur/-Abstand (Grenzen vorläufig 95/105 °C bzw.
  Ø 20/30 °C über Kern), Abbruch per Strg+C eigener WARN-Punkt, lastabhängige Punkte SKIP bei zu wenig Daten.
- Real verifiziert: Erkennung, Felder, memtest_vulkan, gpu-burn, vkmark, gddr6 (Secure Boot aus), Lüfter-RPM.
- v1.4 real verifiziert (RTX 3090, 2026-10-27, Quick, GESAMT PASS): gputemps liefert VRAM (max 96 °C) und Hotspot
  (max 93 °C, Ø 18,6 °C über Kern bei 345 W); Desktop-Layout auf 2560×1440 korrekt.
  Offen: Grenzwert-Kalibrierung mit mehr Karten (bisher nur eine 3090), Ada/Blackwell ungetestet.

## Hinweise zur Fehlersuche
- Kernel-Log: `journalctl -k -b | grep -Ei 'nvrm|xid|nvidia'`
- Feldnamen prüfen: `nvidia-smi --help-query-gpu`
- Skript-Ausgabe einzelner Teile: z. B. `gpu-check --quick --no-memtest --no-burn --no-gl`
- Änderungen am Skript: vorher Kopie anlegen (`/opt/gpucheck/gpu-check.sh.bak`), danach
  `bash -n` prüfen. Kopie für den Nutzer auch nach `/mnt/reports/gpu-check.sh` legen.
