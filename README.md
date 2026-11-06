# GPU-Check-Stick

**Einfache Anleitung, Download und Textvorlagen für Kleinanzeigen: <https://yankee200076.github.io/gpucheck-stick/>**

Bootfähiger USB-Stick zum **Prüfen gebrauchter Grafikkarten vor dem Kauf**:
- **NVIDIA:** Ampere (RTX 30xx), Ada (RTX 40xx), Blackwell (RTX 50xx)
- **AMD** (seit v1.5): RDNA2 (RX 6000), RDNA3 (RX 7000), RDNA4 (RX 9000)

Karte in einen Test-PC stecken, vom Stick booten, Icon doppelklicken – nach 5 bzw. 20 Minuten
gibt es ein **PASS / WARN / FAIL** mit Begründung und einen Report auf dem Stick.

- Ubuntu 26.04 LTS, NVIDIA-Treiber 595 (Open-Kernel-Module, von Canonical signiert), AMD: amdgpu + Mesa/RADV
- bootet per UEFI, auch mit **Secure Boot**; legt keine Boot-Einträge im fremden PC an
- Test läuft **komplett offline**; Desktop mit Autologin, kein Setup

## Was geprüft wird

| Test | Werkzeug |
|---|---|
| Identifikation: Device-ID, Name, VBIOS, VRAM-Größe, PCIe-Link | nvidia-smi bzw. amdgpu-sysfs, lspci |
| VRAM-Speichertest | [memtest_vulkan](https://github.com/GpuZelenograd/memtest_vulkan) |
| CUDA-Volllast mit Rechenfehler-Prüfung (nur NVIDIA; bei AMD lastet memtest_vulkan bis zum Power-Limit aus) | [gpu-burn](https://github.com/wilicc/gpu-burn) |
| Grafiklast (Vulkan), Sichtprüfung auf Artefakte | vkmark |
| Temperaturen, Takt, Leistung, Lüfter, Throttle-Gründe (1 Hz) | nvidia-smi, nvidia-settings; AMD: hwmon |
| VRAM- und Hotspot-Temperatur, Hotspot-Abstand zum Kern (NVIDIA: Secure Boot aus; AMD: immer) | [gputemps](https://github.com/ThomasBaruzier/gddr6-core-junction-vram-temps); AMD: hwmon |
| Xid- bzw. amdgpu-Fehler (Ring-Timeout, GPU-Reset), PCIe-Fehler (AER) | Kernel-Log |

Grenzwerte pro Generation sind in [`gpu-check.sh`](gpu-check.sh) (Funktion `set_limits`) kommentiert.

## Download und Stick erstellen

**Image:** `gpucheck.img.xz` (ca. 2,7 GB) auf SourceForge: **<https://sourceforge.net/projects/gpucheck-stick/files/v1.5/>**
(dort auch `gpucheck.img.xz.sha256`, SHA256 `SHA_V15`)

USB-Stick **ab 16 GB**, mit **Rufus** (Windows), **balenaEtcher** oder `dd` aufspielen.
Details, Bedienung vor Ort und Deutung der Ergebnisse: **[ANLEITUNG.md](ANLEITUNG.md)**.

Zugang: Benutzer `gpu`, Passwort `gpu` (Autologin, `sudo` ohne Passwort).

## Stand

- Auf echter Hardware getestet: **RTX 3090** (Ampere) mit Treiber 595 und **RX 6900 XT** (RDNA2),
  jeweils inklusive VRAM- und Hotspot-Temperatur.
- Ada, Blackwell, RDNA3 und RDNA4: Code und Grenzwerte vorhanden, **noch nicht auf echter Karte getestet**.
  Rückmeldungen mit Report (`summary.txt` + `report.txt`) gern als Issue.

## Repository

| Pfad | Inhalt |
|---|---|
| `gpu-check.sh` | das Testskript (läuft auch auf jedem anderen Linux mit NVIDIA-Treiber oder amdgpu) |
| `ANLEITUNG.md` | Anleitung für Stick und Test (liegt auch auf dem Stick) |
| `build/` | Skripte, mit denen das System gebaut wurde, siehe [build/BUILD.md](build/BUILD.md) |
| `build/mock/` | Testumgebung: simulierte RTX 3090 (gut/defekt) zum Testen ohne Karte |
| `LIZENZEN.md` | Lizenzen aller Bestandteile des Images |

## Lizenz

Eigene Skripte: [MIT](LICENSE). Bestandteile des Images: siehe [LIZENZEN.md](LIZENZEN.md).

Keine Gewähr: Der Test senkt das Risiko eines Fehlkaufs, kann aber nicht jeden Defekt finden
(siehe Abschnitt „Was der Test NICHT erkennt“ in der Anleitung).
