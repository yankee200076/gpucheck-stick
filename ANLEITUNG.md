# GPU-Check-Stick – Anleitung für vor Ort

Bootfähiger USB-Stick zum Prüfen gebrauchter NVIDIA-Grafikkarten
(Ampere RTX 30xx, Ada RTX 40xx, Blackwell RTX 50xx).
Ubuntu 26.04 LTS, NVIDIA-Treiber 595 (Open-Kernel-Module). Der Test läuft komplett offline;
Internet ist nur für Browser, Claude Code und opencode nötig.

Benutzer: `gpu`, Passwort: `gpu` (Autologin, `sudo` ohne Passwort)

---

## 0. Stick erstellen (aus dem Image)

Benötigt: USB-Stick **ab 16 GB** (USB 3 empfohlen). **Alle Daten darauf werden gelöscht.**

- **Windows: Rufus** – Gerät wählen, bei „Startart“ die Datei `gpucheck.img.xz` auswählen
  (Rufus erkennt sie als DD-Image und schreibt sie 1:1), „Start“.
- **Windows/macOS/Linux: balenaEtcher** – „Flash from file“, Stick wählen, „Flash“.
- **Linux:** `xzcat gpucheck.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync`
- Prüfsumme vorher vergleichen: `sha256sum gpucheck.img.xz` mit `gpucheck.img.xz.sha256`.

Beim **ersten Start** vergrößert sich das System automatisch auf die ganze Stick-Größe (einige Sekunden).
Windows zeigt nach dem Aufspielen nur das Laufwerk **GPUREPORTS** an (und meldet evtl., ein
Laufwerk müsse formatiert werden – **nicht formatieren**, das ist die Linux-Partition).

## 1. Vorbereitung (zu Hause)

- **Test-PC** mit ausreichendem Netzteil. RTX 3090: je nach Modell 2–3× 8-Pin, mindestens 750 W.
  RTX 4090/5090: 12VHPWR/12V-2x6, mindestens 850–1000 W.
  **Jeden 8-Pin-Stecker mit einem eigenen Kabel** vom Netzteil anschließen, keine Y-Kabel.
- Im BIOS des Test-PCs einmalig einstellen:
  - **Boot-Modus: UEFI** (CSM/Legacy aus)
  - **Secure Boot: AUS**, wenn du die **VRAM-Temperatur** sehen willst. Das ist bei der 3090 wichtig.
    Dafür vorher einmal (mit Internet) das Icon **„VRAM-Temperatur nachrüsten“** starten, siehe unten.
    Mit Secure Boot AN läuft alles andere trotzdem: Treiber und Bootloader sind signiert.
  - Above 4G Decoding / Resizable BAR: egal
- Monitor-Kabel (DP und HDMI) mitnehmen. **Den Monitor an die Testkarte anschließen,
  nicht an die Mainboard-Grafik**, sonst bleiben Bildausgänge und Artefakte ungetestet.
  Optional nacheinander jeden Ausgang der Karte kurz testen.

## 2. Booten

1. Karte einbauen, alle Stromstecker einrasten lassen, Monitor an die Karte.
2. Stick einstecken, PC einschalten, **Boot-Menü** aufrufen:
   - ASUS: **F8** · MSI: **F11** · Gigabyte: **F12** · ASRock: **F11** · Dell: **F12** · Lenovo: **F12** · HP: **F9**
3. Den Eintrag **„UEFI: <Stickname>“** wählen (nicht den ohne „UEFI“).
4. GRUB-Menü (5 s):
   - **GPU-Check** – Standard
   - *Textmodus* – falls der Desktop nicht startet. Dann einloggen (`gpu`/`gpu`)
     und `gpu-check --quick` eingeben.
   - *Notfall-Grafik* – ohne NVIDIA-Treiber, nur zur Diagnose („wird die Karte überhaupt erkannt?“)
5. Nach ca. 30–60 s erscheint der XFCE-Desktop (automatische Anmeldung).

## 3. Test starten

Auf dem Desktop doppelklicken:

| Icon | Dauer | Inhalt |
|---|---|---|
| **GPU-Schnelltest** | ~5 Min. | Idle 15 s, VRAM 2 Min., CUDA-Last 2 Min., Grafik 30 s |
| **GPU-Volltest** | ~20 Min. | Idle 30 s, VRAM 5,5 Min., CUDA-Last 10 Min., Grafik 2 Min. |
| nvtop | – | Live-Anzeige (Temperatur, Takt, Last) |
| Reports öffnen | – | Ordner mit allen Reports |
| Chromium | – | Browser |
| Claude Code / opencode | – | KI-Assistent im Terminal (Fehlersuche, braucht Internet) |
| VRAM-Temperatur nachrüsten | 1–2 Min. | einmalig, braucht Internet – siehe Abschnitt 8 |

Fragt der Desktop beim ersten Doppelklick „Nicht vertrauenswürdiger Starter“,
dann **„Ausführen markieren“** wählen.

Empfehlung: Zuerst den **Schnelltest**. Ist er grün und der Verkäufer hat Zeit, folgt der **Volltest**.
Die VRAM-Temperatur einer 3090 steigt erst nach mehreren Minuten auf ihren Endwert.

**Während der Grafiklast** (vkmark, Vollbild) auf den Bildschirm schauen:
bunte Punkte, Streifen, Schachbrettmuster, Flackern oder Blackscreen bedeuten einen Defekt.
Danach fragt das Skript, ob du Bildfehler gesehen hast (`j` oder Enter für Nein).

Abbrechen: **Strg+C** im Terminal. Ein Teil-Report wird trotzdem gespeichert.

Kommandozeile, falls gebraucht:

```
gpu-check --quick              # Schnelltest
gpu-check --full               # Volltest
gpu-check --full --burn 1200   # 20 Min. CUDA-Last
gpu-check --help               # alle Optionen
```

## 4. Report lesen

Am Ende erscheinen ein Fenster und die Terminalausgabe mit einer Zeile pro Prüfpunkt:

- **PASS**: in Ordnung
- **WARN**: auffällig, abwägen (Preis verhandeln, nachfragen)
- **FAIL**: harter Fehler, **nicht kaufen**
- INFO/SKIP: nur Information, bzw. Test nicht möglich

| Prüfpunkt | FAIL bedeutet typischerweise |
|---|---|
| VRAM-Größe | Fälschung oder umgeflashtes BIOS |
| VRAM-Test | defekter Speicherchip oder Speichercontroller |
| CUDA-Rechenfehler | GPU rechnet falsch (instabil/defekt) |
| GPU-Temperatur | Kühler, Wärmeleitpaste, Montage |
| VRAM-Temperatur | Wärmeleitpads verschlissen (3090: Rückseite!) |
| Throttle-Gründe | HW-Slowdown/Power-Brake: Stromversorgung, Stecker, Spannungswandler |
| Leistungsaufnahme | Karte zieht keine Volllast (Strommess-/VRM-Problem) |
| Lüfter | Lüfter steht oder läuft nicht hoch |
| PCIe-Link | WARN: Gen/Breite reduziert, Kontakte/Steckplatz/Riser |
| Xid-Fehler | Treiber meldet Hardwarefehler (z. B. Xid 79: vom Bus gefallen) |

Der Report liegt auf dem Stick in der Partition **GPUREPORTS** (exFAT, unter
Windows/macOS lesbar), z. B. `2026-10-25_143012_NVIDIA_GeForce_RTX_3090/`:

- `summary.txt`: Zusammenfassung
- `report.txt`: vollständiges Protokoll
- `monitor.csv`, `burn.csv`, …: Messwerte pro Sekunde (in Excel/LibreOffice öffnen)
- `nvidia-smi-q.txt`, `lspci.txt`, `kernel.log`: Rohdaten
- `memtest_vulkan.out`, `gpu_burn.out`, `vkmark.out`: Ausgaben der Testprogramme

## 5. Was der Test NICHT erkennt

- **Spulenfiepen**: Ohr an die Karte während der CUDA-Last.
- Geruch (verschmortes Bauteil), sichtbare Schäden, fehlende Schrauben, Garantiesiegel:
  ansehen. Eine Taschenlampe hilft beim Prüfen der PCIe-Kontakte und Stromstecker
  auf Verfärbung.
- **Hotspot-Temperatur**: NVIDIA stellt sie unter Linux für GeForce nicht bereit.
  Ein hoher Hotspot-Abstand fällt indirekt durch Drosselung auf („Throttle-Gründe“/„Takt unter Last“).
- **Langzeitstabilität** (Stunden): Dafür reicht kein Test beim Verkäufer.
- Seriennummer: GeForce-Karten melden sie meist nicht (`N/A`). Den Aufkleber auf der Karte prüfen.

## 6. Grenzwerte (Kurzfassung)

| Wert | WARN | FAIL |
|---|---|---|
| GPU-Temperatur unter Last | ≥ 81 °C | ≥ 87 °C |
| VRAM GDDR6X (Ampere 3080/3090) | ≥ 100 °C | ≥ 106 °C |
| VRAM GDDR6/GDDR6X (Ada), GDDR7 (Blackwell) | ≥ 90 °C | ≥ 100 °C |
| Leistung unter CUDA-Last | < 75 % Power-Limit | < 50 % |
| SM-Takt unter Last | < Basistakt | < 85 % Basistakt |
| SW-Thermal-Drosselung | ≥ 10 % der Zeit | – |
| HW-Slowdown / HW-Thermal / Power-Brake | vereinzelt | ≥ 2 % der Zeit |

Begründungen stehen als Kommentar in `/opt/gpucheck/gpu-check.sh` (Funktion `set_limits`).
Gemessen wird bei offenem Aufbau und ca. 20–25 °C Raumtemperatur. In einem warmen
Gehäuse liegen die Werte einige Grad höher.

## 7. Probleme

- **Stick erscheint nicht im Boot-Menü**: CSM/Legacy aus, UEFI an. Anderen USB-Port probieren (hinten am Mainboard).
- **„Verification failed“ / „Security Violation“**: Secure Boot aus.
- **Schwarzer Bildschirm nach GRUB**: Monitor am anderen Ausgang der Karte probieren,
  sonst den GRUB-Eintrag *Textmodus* wählen und `gpu-check --quick` starten.
- **„nvidia-smi sieht die Karte nicht“**: Der Report enthält die Kernel-Meldungen.
  `RmInitAdapter failed` deutet auf eine defekte Karte hin.
  Erscheint sie unter `lspci` gar nicht: Steckplatz, Stromstecker, anderer PC.

## 8. Internet und Claude Code

- **LAN**: Kabel einstecken, die Verbindung kommt automatisch.
- **WLAN**: Netzwerk-Symbol oben rechts im Panel, Netz wählen, Passwort eingeben.
- **Claude Code**: Icon „Claude Code (Fehlersuche)“ oder `claude` im Terminal. Claude Code ist
  nicht im Image enthalten: Beim ersten Aufruf wird es aus dem Internet installiert, danach
  öffnet sich Chromium zur Anmeldung (eigenes Claude-Konto nötig). Claude liest `~/CLAUDE.md` und kennt damit
  Aufbau, Werkzeuge und Pfade des Sticks.
- **opencode**: Icon oder `opencode` im Terminal (enthält kostenlose Modelle, Anmeldung optional).
- **VRAM-Temperatur nachrüsten**: Das Messwerkzeug *gddr6* hat keine Lizenz und darf deshalb nicht
  im Image liegen. Das Icon lädt es vom Original-Projekt (github.com/olealgoritme/gddr6) und baut es
  auf dem Stick – **einmal zu Hause mit Internet erledigen**, danach funktioniert es offline.
  Ohne das Werkzeug meldet der Test bei der VRAM-Temperatur „SKIP“.
- Die Anmeldedaten bleiben auf dem Stick gespeichert. Wer den Stick hat, hat Zugriff
  auf dein Konto. Bei Verlust in den Konto-Einstellungen abmelden.

## 9. Inhalt / Versionen

- Ubuntu 26.04 LTS, Kernel 7.0 (generic), NVIDIA 595.99.02 open (signiert von Canonical)
- memtest_vulkan v0.5.0 (GpuZelenograd, Prebuilt)
- gpu-burn (wilicc, Commit 0d19c94, gebaut mit CUDA 13.4 für sm_86/sm_89/sm_120 + PTX; Bibliotheken liegen in `/opt/gpucheck/gpu-burn/lib`)
- gddr6 (olealgoritme, Commit 586c77a): VRAM-Temperatur, **per Icon nachzurüsten**, braucht `iomem=relaxed` (gesetzt) und Secure Boot AUS
- vkmark, glmark2, nvtop, nvidia-smi, nvidia-settings, stress-ng, lm-sensors
- Chromium 156 (xtradeb-PPA, deb statt Snap), opencode 1.19.4; Claude Code wird beim ersten Aufruf installiert
- gpu-check.sh 1.3: auf echter RTX 3090 getestet (Kartenerkennung, Basistakt-Tabelle für Treiber 59x,
  Lüfter-RPM, vkmark-Ende, Auswertung nur unter Last)
