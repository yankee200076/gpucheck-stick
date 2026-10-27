# GPU-Check-Stick

**Einfache Anleitung, Download und Textvorlagen für Kleinanzeigen: <https://yankee200076.github.io/gpucheck-stick/>**

Bootfähiger USB-Stick zum **Prüfen gebrauchter NVIDIA-Grafikkarten vor dem Kauf**:
Ampere (RTX 30xx), Ada (RTX 40xx), Blackwell (RTX 50xx).

Karte in einen Test-PC stecken, vom Stick booten, Icon doppelklicken – nach 5 bzw. 20 Minuten
gibt es ein **PASS / WARN / FAIL** mit Begründung und einen Report auf dem Stick.

- Ubuntu 26.04 LTS, NVIDIA-Treiber 595 (Open-Kernel-Module, von Canonical signiert)
- bootet per UEFI, auch mit **Secure Boot**; legt keine Boot-Einträge im fremden PC an
- Test läuft **komplett offline**; Desktop mit Autologin, kein Setup

## Was geprüft wird

| Test | Werkzeug |
|---|---|
| Identifikation: Device-ID, Name, VBIOS, VRAM-Größe, PCIe-Link | nvidia-smi, lspci |
| VRAM-Speichertest | [memtest_vulkan](https://github.com/GpuZelenograd/memtest_vulkan) |
| CUDA-Volllast mit Rechenfehler-Prüfung | [gpu-burn](https://github.com/wilicc/gpu-burn) |
| Grafiklast (Vulkan), Sichtprüfung auf Artefakte | vkmark |
| Temperaturen, Takt, Leistung, Lüfter, Throttle-Gründe (1 Hz) | nvidia-smi, nvidia-settings |
| VRAM- und Hotspot-Temperatur, Hotspot-Abstand zum Kern (Secure Boot aus) | [gputemps](https://github.com/ThomasBaruzier/gddr6-core-junction-vram-temps) |
| Xid-Fehler, PCIe-Fehler (AER) | Kernel-Log |

Grenzwerte pro Generation sind in [`gpu-check.sh`](gpu-check.sh) (Funktion `set_limits`) kommentiert.

## Download und Stick erstellen

**Image:** `gpucheck.img.xz` (ca. 2,7 GB) auf SourceForge: **<https://sourceforge.net/projects/gpucheck-stick/files/v1.4/>**
(dort auch `gpucheck.img.xz.sha256`, SHA256 `54ba53eab57997457966c43eb9b78b0d479bea80a4addf383e0479b95dbfcf3f`)

USB-Stick **ab 16 GB**, mit **Rufus** (Windows), **balenaEtcher** oder `dd` aufspielen.
Details, Bedienung vor Ort und Deutung der Ergebnisse: **[ANLEITUNG.md](ANLEITUNG.md)**.

Zugang: Benutzer `gpu`, Passwort `gpu` (Autologin, `sudo` ohne Passwort).

## Stand

- Auf echter Hardware getestet: **RTX 3090** (Ampere) mit Treiber 595, inklusive VRAM- und Hotspot-Temperatur.
- Ada und Blackwell: Code und Grenzwerte vorhanden, **noch nicht auf echter Karte getestet**.
  Rückmeldungen mit Report (`summary.txt` + `report.txt`) gern als Issue.

## Repository

| Pfad | Inhalt |
|---|---|
| `gpu-check.sh` | das Testskript (läuft auch auf jedem anderen Linux mit NVIDIA-Treiber) |
| `ANLEITUNG.md` | Anleitung für Stick und Test (liegt auch auf dem Stick) |
| `build/` | Skripte, mit denen das System gebaut wurde, siehe [build/BUILD.md](build/BUILD.md) |
| `build/mock/` | Testumgebung: simulierte RTX 3090 (gut/defekt) zum Testen ohne Karte |
| `LIZENZEN.md` | Lizenzen aller Bestandteile des Images |

## Lizenz

Eigene Skripte: [MIT](LICENSE). Bestandteile des Images: siehe [LIZENZEN.md](LIZENZEN.md).

Keine Gewähr: Der Test senkt das Risiko eines Fehlkaufs, kann aber nicht jeden Defekt finden
(siehe Abschnitt „Was der Test NICHT erkennt“ in der Anleitung).
