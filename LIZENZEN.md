# Lizenzen der Bestandteile

Das Image `gpucheck.img.xz` ist eine Zusammenstellung. Jeder Bestandteil steht unter seiner eigenen Lizenz.

| Bestandteil | Version | Lizenz | Quelle |
|---|---|---|---|
| Eigene Skripte (`gpu-check.sh`, `build/*`) | – | MIT, siehe [LICENSE](LICENSE) | dieses Repository |
| Ubuntu (Basissystem, Kernel, XFCE, …) | 26.04 LTS | überwiegend GPL/LGPL/MIT/BSD; Texte im Image unter `/usr/share/doc/<paket>/copyright` | ubuntu.com |
| NVIDIA-Kernelmodule (open) | 595.99.02 | MIT / GPL-2.0 (dual) | Ubuntu-Paket `linux-modules-nvidia-595-open-generic` |
| NVIDIA-Treiber (Userspace, nvidia-smi, nvidia-settings) | 595.99.02 | NVIDIA-Softwarelizenz; unverändert aus den Ubuntu-Paketquellen (`restricted`) | Ubuntu-Paket `nvidia-driver-595-open` |
| CUDA-Laufzeit `libcudart`, `libcublas`, `libcublasLt` | 13.4 | NVIDIA CUDA EULA – als „redistributable“ freigegeben (Anhang A) | developer.nvidia.com/cuda |
| gputemps (VRAM-/Hotspot-Temperatur) | Commit 6d8c5ec | Apache-2.0; Lizenztext im Image unter `/usr/share/doc/gputemps/`, Quellcode unter `/opt/gpucheck/src/` | github.com/ThomasBaruzier/gddr6-core-junction-vram-temps |
| memtest_vulkan | 0.5.0 | Zlib | github.com/GpuZelenograd/memtest_vulkan |
| gpu-burn | Commit 0d19c94 | BSD-2-Clause; Quellcode mit Lizenztext im Image unter `/opt/gpucheck/src/` | github.com/wilicc/gpu-burn |
| Chromium | 156 | BSD-3-Clause u. a. | xtradeb-PPA (Ubuntu-Build) |
| opencode | 1.19.4 | MIT | opencode.ai |
| vkmark, glmark2, nvtop, stress-ng | Ubuntu-Pakete | LGPL-2.1 / GPL-3.0 / GPL-3.0 / GPL-2.0 | Ubuntu |

## Nicht im Image enthalten

- **gddr6** (github.com/olealgoritme/gddr6): hat **keine Lizenz** und ist deshalb nicht enthalten; ersetzt
  durch gputemps (Apache-2.0), das gddr6 als Quelle für die Register-Adressen nennt.
- **Claude Code**: proprietär; wird beim ersten Aufruf von `claude` vom Hersteller installiert.

Die Einschätzungen zu NVIDIA-Treiber und CUDA beruhen auf den Lizenztexten der Hersteller und darauf,
dass Ubuntu diese Pakete selbst verteilt. Sie sind keine Rechtsberatung.
