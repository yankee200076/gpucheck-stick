#!/bin/bash
# =============================================================================
# gpu-check.sh – Prüfung gebrauchter NVIDIA-Grafikkarten (Ampere … Blackwell)
#
#   gpu-check.sh --quick        Schnelltest  (~5 Min.)
#   gpu-check.sh --full         Volltest     (~20 Min.)
#   gpu-check.sh --help         alle Optionen
#
# Ablauf: Identifikation -> Leerlauf -> VRAM-Test (memtest_vulkan)
#         -> CUDA-Volllast (gpu-burn) -> Vulkan-Grafiklast (vkmark)
#         -> Kernel-Log (Xid/AER) -> Zusammenfassung PASS/WARN/FAIL
#
# Ergebnis: Ordner mit Zeitstempel auf der Partition GPUREPORTS des Sticks.
# =============================================================================
set -u
VERSION="1.3"
# Zahlen immer mit Punkt (CSV, printf, awk) – Texte bleiben deutsch/UTF-8
[ -n "${LC_ALL:-}" ] && export LANG="$LC_ALL"
unset LC_ALL
export LC_NUMERIC=C

# ----------------------------------------------------------------- Pfade -----
GPUCHECK_HOME=${GPUCHECK_HOME:-/opt/gpucheck}
MEMTEST_BIN=${MEMTEST_BIN:-$GPUCHECK_HOME/bin/memtest_vulkan}
GPUBURN_DIR=${GPUBURN_DIR:-$GPUCHECK_HOME/gpu-burn}
GDDR6_BIN=${GDDR6_BIN:-$GPUCHECK_HOME/bin/gddr6}
REPORT_ROOT=${REPORT_ROOT:-/mnt/reports}
NV_ICD=${NV_ICD:-/usr/share/vulkan/icd.d/nvidia_icd.json}
DESKTOP_USER=${DESKTOP_USER:-gpu}
PCI_SYSFS=${PCI_SYSFS:-/sys/bus/pci/devices}

# ----------------------------------------------------------- Parameter -------
MODE=quick
GPU=0            # nvidia-smi-Index der zu prüfenden Karte
ASK=1            # nach sichtbaren Bildfehlern fragen
DO_MEMTEST=1 DO_BURN=1 DO_GL=1
T_IDLE= T_MEMTEST= T_BURN= T_GL=

usage() {
cat <<EOF
gpu-check.sh $VERSION – Gebrauchtkarten-Check für NVIDIA-GPUs

  -q, --quick          Schnelltest (Standard): Idle 15 s, VRAM 120 s, CUDA 120 s, Vulkan 30 s
  -f, --full           Volltest:               Idle 30 s, VRAM 330 s, CUDA 600 s, Vulkan 120 s
      --memtest SEK    Dauer VRAM-Test überschreiben
      --burn SEK       Dauer CUDA-Volllast überschreiben
      --gl SEK         Dauer Vulkan-Grafiklast überschreiben
      --idle SEK       Dauer Leerlaufmessung überschreiben
      --no-memtest | --no-burn | --no-gl   Teiltests auslassen
      --gpu N          Karte N laut nvidia-smi-Index (Standard 0)
      --no-ask         nicht nach Bildfehlern fragen (unbeaufsichtigt)
      --out DIR        Report-Verzeichnis (Standard $REPORT_ROOT)
  -h, --help           diese Hilfe
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -q|--quick) MODE=quick ;;
        -f|--full)  MODE=full ;;
        --memtest)  T_MEMTEST=$2; shift ;;
        --burn)     T_BURN=$2; shift ;;
        --gl)       T_GL=$2; shift ;;
        --idle)     T_IDLE=$2; shift ;;
        --no-memtest) DO_MEMTEST=0 ;;
        --no-burn)  DO_BURN=0 ;;
        --no-gl)    DO_GL=0 ;;
        --gpu)      GPU=$2; shift ;;
        --no-ask)   ASK=0 ;;
        --out)      REPORT_ROOT=$2; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "Unbekannte Option: $1"; usage; exit 2 ;;
    esac
    shift
done

if [ "$MODE" = full ]; then
    : "${T_IDLE:=30}" "${T_MEMTEST:=330}" "${T_BURN:=600}" "${T_GL:=120}"
else
    : "${T_IDLE:=15}" "${T_MEMTEST:=120}" "${T_BURN:=120}" "${T_GL:=30}"
fi
for v in T_IDLE T_MEMTEST T_BURN T_GL GPU; do
    [[ ${!v} =~ ^[0-9]+$ ]] || { echo "$v muss eine Zahl sein"; exit 2; }
done

# Root nötig (dmesg, /dev/mem für VRAM-Temperatur). Desktop-Umgebung mitnehmen.
if [ "$(id -u)" -ne 0 ]; then
    exec sudo --preserve-env=DISPLAY,XAUTHORITY,WAYLAND_DISPLAY,XDG_RUNTIME_DIR "$0" \
        $([ $MODE = full ] && echo --full || echo --quick) --memtest "$T_MEMTEST" --burn "$T_BURN" \
        --gl "$T_GL" --idle "$T_IDLE" --gpu "$GPU" --out "$REPORT_ROOT" \
        $([ $ASK = 0 ] && echo --no-ask) $([ $DO_MEMTEST = 0 ] && echo --no-memtest) \
        $([ $DO_BURN = 0 ] && echo --no-burn) $([ $DO_GL = 0 ] && echo --no-gl)
fi

# ------------------------------------------------------------ Ausgabe --------
if [ -t 1 ]; then
    C_R=$'\e[1;31m' C_G=$'\e[1;32m' C_Y=$'\e[1;33m' C_B=$'\e[1;36m' C_0=$'\e[0m'
else
    C_R= C_G= C_Y= C_B= C_0=
fi
STAMP=$(date +%Y-%m-%d_%H%M%S)
START_EPOCH=$(date +%s)
START_ISO=$(date '+%Y-%m-%d %H:%M:%S')

declare -a R_NAME R_STATE R_MSG
result() {  # result NAME PASS|WARN|FAIL|INFO|SKIP "Text"
    R_NAME+=("$1"); R_STATE+=("$2"); R_MSG+=("$3")
    local c=$C_0
    case $2 in PASS) c=$C_G;; WARN) c=$C_Y;; FAIL) c=$C_R;; *) c=$C_B;; esac
    printf '  %s%-4s%s  %s %s\n' "$c" "$2" "$C_0" "$(pad "$1" 24)" "$3" | tee -a "$LOG"
}
pad() { local s=$1; printf '%s%*s' "$s" $(( $2 > ${#s} ? $2 - ${#s} : 0 )) ''; }   # zeichen- statt bytegenau
say()   { printf '%s\n' "$*" | tee -a "$LOG"; }
phase() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; printf '\n== %s ==\n' "$*" >> "$LOG"; }

# ------------------------------------------------------------ Report-Ordner --
if ! mountpoint -q "$REPORT_ROOT" 2>/dev/null && [ "$REPORT_ROOT" = /mnt/reports ]; then
    mount LABEL=GPUREPORTS /mnt/reports 2>/dev/null || true
fi
mkdir -p "$REPORT_ROOT" 2>/dev/null && [ -w "$REPORT_ROOT" ] || REPORT_ROOT=/root/gpu-reports
TMPDIR_RUN=$(mktemp -d /tmp/gpucheck.XXXX)
DIR="$TMPDIR_RUN"       # wird nach Identifikation in den Report-Ordner verschoben
LOG="$DIR/report.txt"
: > "$LOG"

# --------------------------------------------------------- Aufräumen ---------
BG_PIDS=()
cleanup() {
    for p in "${BG_PIDS[@]}"; do kill "$p" 2>/dev/null; done
    pkill -f "$GPUBURN_DIR/gpu_burn" 2>/dev/null
    pkill -x memtest_vulkan 2>/dev/null
    pkill -x vkmark 2>/dev/null
}
ABORTED=0
on_abort() { ABORTED=1; echo; say "!!! Test abgebrochen (Strg+C) – Report wird trotzdem geschrieben."; cleanup; }
trap on_abort INT TERM
trap cleanup EXIT

smi() { nvidia-smi -i "$GPU" "$@"; }
q1()  { local o; o=$(smi --query-gpu="$1" --format=csv,noheader,nounits 2>/dev/null) || return 0
        echo "$o" | head -1 | sed 's/^ *//; s/ *$//'; }
isnum() { [[ ${1:-} =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; }

# PCIe-Geschwindigkeit "16.0 GT/s PCIe" -> Generation
gt2gen() {
    case "${1%% *}" in 2.5) echo 1;; 5.0) echo 2;; 8.0) echo 3;; 16.0) echo 4;;
                       32.0) echo 5;; 64.0) echo 6;; *) echo "?";; esac
}

# =============================================================================
#  GRENZWERTE  (bewusst konservativ für eine Gebrauchtkarte unter Dauerlast,
#  offenes Gehäuse / Testbench, Raumtemperatur ~20–25 °C)
# =============================================================================
set_limits() {
    local arch=$1 memtype=$2
    # GPU-Kerntemperatur unter Last. NVIDIA-Slowdown liegt bei Ampere/Ada/Blackwell
    # um 83–90 °C (max. 93 °C). Ein gesundes Custom-Design (z. B. Strix) bleibt
    # unter gpu-burn deutlich unter 80 °C. 81–86 °C deutet auf alte Paste/verstaubten
    # Kühler, >= 87 °C auf ein echtes Kühlproblem.
    LIM_CORE_WARN=81; LIM_CORE_FAIL=87
    # Leerlauf: > 55 °C bei 0-RPM-Lüftern möglich, > 65 °C auffällig.
    LIM_IDLE_WARN=65
    # VRAM-Temperatur (nur mit gddr6-Tool, Secure Boot aus):
    #  - Ampere GDDR6X (3080/3090): Throttle bei 110 °C. 3090 hat Speicher auch auf
    #    der Rückseite und wird bekanntlich heiß. Unter memtest_vulkan sind ~84–94 °C
    #    normal, >= 100 °C deutet auf verschlissene Wärmeleitpads, >= 106 °C FAIL.
    #  - Ada GDDR6X läuft deutlich kühler (Speicher nur vorne, bessere Pads).
    #  - Blackwell GDDR7: experimentell ausgelesen, Werte wie Ada.
    case "$arch:$memtype" in
        Ampere:GDDR6X) LIM_VRAM_WARN=100; LIM_VRAM_FAIL=106 ;;
        Ampere:*)      LIM_VRAM_WARN=90;  LIM_VRAM_FAIL=100 ;;
        Ada*:*)        LIM_VRAM_WARN=90;  LIM_VRAM_FAIL=100 ;;
        Blackwell:*)   LIM_VRAM_WARN=90;  LIM_VRAM_FAIL=100 ;;
        *)             LIM_VRAM_WARN=95;  LIM_VRAM_FAIL=105 ;;
    esac
    # T.Limit = Abstand (°C) bis zur Slowdown-Temperatur (NVML). < 5 °C Reserve: WARN.
    LIM_TLIMIT_WARN=5
    # Leistungsaufnahme unter gpu-burn relativ zum aktiven Power-Limit.
    # Gesunde Karten hängen unter gpu-burn praktisch immer am Power-Limit (>= 90 %).
    # < 75 % ohne thermischen Grund: Stromversorgung/Sense-Schaltung/Karte prüfen.
    LIM_PWR_WARN_PCT=75; LIM_PWR_FAIL_PCT=50
    # SM-Takt unter Last relativ zum Basistakt (default applications clock = Base).
    # Unter Basistakt bei voller Last = Karte drosselt übermäßig.
    LIM_CLK_WARN_PCT=100; LIM_CLK_FAIL_PCT=85
    # Throttle-Gründe: Anteil Messpunkte unter Last.
    #  SW Power Cap  -> normal, kein Befund
    #  SW Thermal    -> WARN ab 10 %
    #  HW Thermal / HW Slowdown / HW Power Brake -> FAIL ab 2 %, WARN bei Einzelfällen
    #  (HW Slowdown/Power Brake = Karte meldet Strom-/Spannungsproblem, oft
    #   schlechter 12-V-Stecker, schwaches Netzteil oder Defekt der Spannungswandler)
    LIM_SWTHERM_WARN_PCT=10; LIM_HW_FAIL_PCT=2
    # Lüfter: bei GPU > 65 °C muss der Lüfter >= 30 % laufen; ein einzelner Lüfter
    # mit 0 RPM unter Last (wenn RPM auslesbar) = defekter Lüfter -> FAIL.
    LIM_FAN_MIN_PCT=30
    # Leerlauf-Leistung > 20 % des Default-Power-Limits: WARN (z. B. 3090: > ~70 W).
    LIM_IDLE_PWR_PCT=20
    # Erwartete PCIe-Generation der Karte (max. GPU-seitig)
    case "$arch" in Ampere|Ada*) EXP_GEN=4 ;; Blackwell) EXP_GEN=5 ;; *) EXP_GEN=0 ;; esac
}

# Bekannte Device-IDs -> erwartete VRAM-Größe (GiB). Nur Fälschungs-Plausibilität:
# eine umgeflashte/gefälschte Karte meldet oft eine falsche VRAM-Größe.
expected_vram_gib() {
    case "${1,,}" in
        2204|2203) echo 24 ;;          # RTX 3090 / 3090 Ti
        2208|220a) echo 12 ;;          # RTX 3080 Ti / 3080 12GB
        2206|2216) echo 10 ;;          # RTX 3080 / 3080 LHR
        2482|2484|2488|2486|2489|24c9) echo 8 ;;   # 3070 Ti / 3070 / 3060 Ti
        2503|2504|2544) echo 12 ;;     # RTX 3060
        2684) echo 24 ;;               # RTX 4090
        2702|2704|2705) echo 16 ;;     # 4080 Super / 4080 / 4070 Ti Super
        2782|2783|2786) echo 12 ;;     # 4070 Ti / 4070 Super / 4070
        2b85) echo 32 ;;               # RTX 5090
        2c02|2c05) echo 16 ;;          # RTX 5080 / 5070 Ti
        2f04) echo 12 ;;               # RTX 5070
        *) echo "" ;;
    esac
}

# Bekannte Device-IDs -> Referenz-Basistakt (MHz, NVIDIA-Spezifikation). Ersatz für
# clocks.default_applications.graphics, das ab Treiber 59x "deprecated" liefert.
# Partnerkarten (OC) haben gleichen oder höheren Basistakt -> Referenz = Untergrenze.
ref_base_clk() {
    case "${1,,}" in
        2204) echo 1395 ;;             # RTX 3090
        2203) echo 1560 ;;             # RTX 3090 Ti
        2208) echo 1365 ;;             # RTX 3080 Ti
        220a) echo 1260 ;;             # RTX 3080 12GB
        2206|2216) echo 1440 ;;        # RTX 3080 / 3080 LHR
        2482) echo 1575 ;;             # RTX 3070 Ti
        2484|2488) echo 1500 ;;        # RTX 3070 / 3070 LHR
        2486|2489|24c9) echo 1410 ;;   # RTX 3060 Ti (LHR / GDDR6X)
        2503|2504|2544) echo 1320 ;;   # RTX 3060
        2684) echo 2235 ;;             # RTX 4090
        2702) echo 2295 ;;             # RTX 4080 Super
        2704) echo 2205 ;;             # RTX 4080
        2705) echo 2340 ;;             # RTX 4070 Ti Super
        2782) echo 2310 ;;             # RTX 4070 Ti
        2783) echo 1980 ;;             # RTX 4070 Super
        2786) echo 1920 ;;             # RTX 4070
        2b85) echo 2010 ;;             # RTX 5090
        2c02) echo 2295 ;;             # RTX 5080
        2c05) echo 2295 ;;             # RTX 5070 Ti
        2f04) echo 2325 ;;             # RTX 5070
        *) echo "" ;;
    esac
}

# =============================================================================
#  SAMPLER: jede Sekunde eine CSV-Zeile
# =============================================================================
# Gewünschte Felder in CSV-Reihenfolge; "a|b" = Alternativname (ältere/neuere Treiber).
# Ein ungültiges Feld lässt die GANZE Abfrage scheitern -> probe_fields prüft jedes einzeln
# auf der echten Karte und füllt fehlende Spalten leer auf.
SMI_WANT=(temperature.gpu temperature.memory clocks.sm clocks.mem "power.draw|power.draw.average|power.draw.instant"
          "power.limit|enforced.power.limit" fan.speed utilization.gpu pcie.link.gen.current pcie.link.width.current
          "clocks_event_reasons.active|clocks_throttle_reasons.active" pstate memory.used temperature.gpu.tlimit)
SMI_FIELDS=""; SMI_MAP=""; HAVE_TLIMIT=0
probe_fields() {
    local w f ok
    SMI_FIELDS=""; SMI_MAP=""
    for w in "${SMI_WANT[@]}"; do
        ok=""
        for f in ${w//|/ }; do
            if smi --query-gpu="$f" --format=csv,noheader,nounits >/dev/null 2>&1; then ok=$f; break; fi
        done
        if [ -n "$ok" ]; then SMI_FIELDS+="${SMI_FIELDS:+,}$ok"; SMI_MAP+="1 "
        else SMI_MAP+="0 "; say "  Hinweis: nvidia-smi-Feld '$w' nicht verfügbar – Spalte bleibt leer"; fi
        [ "$ok" = temperature.gpu.tlimit ] && HAVE_TLIMIT=1
    done
}
# Abfrageergebnis (nur gültige Felder) auf volle Spaltenzahl auffächern
expand_line() { awk -F, -v map="$SMI_MAP" 'BEGIN{n=split(map,m," ")} {j=1; o=""; for(i=1;i<=n;i++){ v=""; if(m[i]==1){v=$j; j++}; o=o (i>1?",":"") v }; print o}'; }
CSV_HEADER="t,phase,gpu_temp,mem_temp_nvml,sm_clk,mem_clk,power_w,power_limit_w,fan_pct,util_pct,pcie_gen,pcie_width,throttle,pstate,mem_used_mib,tlimit,vram_temp,fan_rpm"

GDDR6_RAW=""
vram_temp_now() {
    [ -n "$GDDR6_RAW" ] && [ -s "$GDDR6_RAW" ] || { echo ""; return; }
    tail -c 300 "$GDDR6_RAW" | tr '\r' '\n' | grep -o '[0-9]\+°C' | tail -1 | tr -dc '0-9'
}

FAN_RPM_OK=0
fan_rpm_now() {   # "1520;1490;1510" – je Lüfter, über nvidia-settings (braucht X auf der NVIDIA-Karte)
    # Ziel [fan] explizit: bei DISPLAY=:0.0 fragt nvidia-settings sonst nur den X-Screen ab -> leer
    [ "$FAN_RPM_OK" = 1 ] || { echo ""; return; }
    runuser -u "$DESKTOP_USER" -- env DISPLAY="$DISPLAY" XAUTHORITY="${XAUTHORITY:-/home/$DESKTOP_USER/.Xauthority}" \
        timeout 3 nvidia-settings -q '[fan]/GPUCurrentFanSpeedRPM' 2>/dev/null \
        | sed -n 's/.*\[fan:\([0-9]*\)\]): \([0-9]*\).*/\2/p' | paste -sd';'
}

sampler() {   # sampler PHASE CSV
    local ph=$1 out=$2 t0 n=0 line rpm=""
    t0=$(date +%s.%N)
    while :; do
        line=$(smi --query-gpu="$SMI_FIELDS" --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ' | expand_line)
        # Lüfter-RPM nur alle 3 s (nvidia-settings ist langsam)
        if [ $((n % 3)) -eq 0 ]; then rpm=$(fan_rpm_now); fi
        printf '%.1f,%s,%s,%s,%s\n' "$(echo "$(date +%s.%N) - $t0" | bc)" "$ph" "$line" "$(vram_temp_now)" "$rpm" >> "$out"
        n=$((n+1))
        sleep 1
    done
}
start_sampler() { echo "$CSV_HEADER" > "$2"; sampler "$1" "$2" & SAMPLER_PID=$!; BG_PIDS+=($SAMPLER_PID); }
stop_sampler()  { kill "$SAMPLER_PID" 2>/dev/null; wait "$SAMPLER_PID" 2>/dev/null; }

# Statistik über eine Spalte (Name) einer Phase; SKIP = erste N Sekunden ignorieren (Aufheizen)
stat() {   # stat CSV SPALTE max|min|avg|mode [SKIP]
    awk -F, -v col="$2" -v fn="$3" -v skip="${4:-0}" '
        NR==1 { for (i=1;i<=NF;i++) if ($i==col) c=i; next }
        $1 < skip { next }
        { v=$c; if (v=="" || v ~ /N\/A|\[|Not/) next
          if (fn=="mode") { cnt[v]++; next }
          v+=0; n++; s+=v; if (n==1||v>mx) mx=v; if (n==1||v<mn) mn=v }
        END { if (fn=="mode") { b=""; for (k in cnt) if (b==""||cnt[k]>cnt[b]) b=k; print b; exit }
              if (!n) { print ""; exit }
              if (fn=="max") printf "%g\n", mx; else if (fn=="min") printf "%g\n", mn; else printf "%.1f\n", s/n }' "$1"
}
# Anteil Messpunkte (%) in denen Throttle-Bit MASK gesetzt ist
throttle_pct() {   # throttle_pct CSV BIT(dezimal, Zweierpotenz) [SKIP] – portabel, ohne gawk
    awk -F, -v m="$2" -v skip="${3:-0}" '
        function hex(h,  i,x) { h=tolower(substr(h,3)); x=0
            for (i=1;i<=length(h);i++) x=x*16+index("0123456789abcdef",substr(h,i,1))-1; return x }
        NR==1 { for (i=1;i<=NF;i++) if ($i=="throttle") c=i; next }
        $1 < skip { next }
        { v=$c; if (v !~ /^0x/) next; n++; if (int(hex(v)/m)%2==1) k++ }
        END { if (!n) print 0; else printf "%.1f\n", 100*k/n }' "$1"
}
# Minimale Einzellüfter-RPM über die Phase (ab SKIP), leer wenn nicht auslesbar
fan_rpm_min() {
    awk -F, -v skip="${2:-0}" 'NR==1{for(i=1;i<=NF;i++) if($i=="fan_rpm") c=i; next}
        $1<skip||$c==""{next} {n=split($c,a,";"); for(i=1;i<=n;i++){ if(!s||a[i]+0<mn) mn=a[i]+0; s=1 }}
        END{ if(s) print mn }' "$1"
}
# Anteil Messpunkte (%), in denen ein Lüfter 0 RPM hat, während ein anderer >= 500 RPM dreht
fan_dead_pct() {
    awk -F, -v skip="${2:-0}" 'NR==1{for(i=1;i<=NF;i++) if($i=="fan_rpm") c=i; next}
        $1<skip||$c==""{next} {n=split($c,a,";"); mn=-1; mx=0
            for(i=1;i<=n;i++){ v=a[i]+0; if(mn<0||v<mn) mn=v; if(v>mx) mx=v }
            s++; if(n>1 && mn==0 && mx>=500) k++ }
        END{ if(!s) print 0; else printf "%.0f\n", 100*k/s }' "$1"
}
num_fans() { awk -F, 'NR==1{for(i=1;i<=NF;i++) if($i=="fan_rpm") c=i; next} $c!=""{n=split($c,a,";"); if(n>m)m=n} END{print m+0}' "$1"; }

# ge/lt mit Kommazahlen
fge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }
flt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<b)}'; }

# =============================================================================
say "gpu-check.sh $VERSION   Modus: $MODE   Start: $START_ISO"
say "Dauer: Idle ${T_IDLE}s, VRAM $([ $DO_MEMTEST = 1 ] && echo ${T_MEMTEST}s || echo aus), CUDA $([ $DO_BURN = 1 ] && echo ${T_BURN}s || echo aus), Vulkan $([ $DO_GL = 1 ] && echo ${T_GL}s || echo aus)"
say "Host: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name 2>/dev/null) / Board $(cat /sys/class/dmi/id/board_vendor 2>/dev/null) $(cat /sys/class/dmi/id/board_name 2>/dev/null)"
say "Kernel $(uname -r), Treiber $(cat /sys/module/nvidia/version 2>/dev/null || echo 'nicht geladen')"

# ============================================================ 1. Identifikation
phase "1. Karte identifizieren"

mapfile -t NV_BDFS < <(lspci -D -d 10de: -n | awk '$2 ~ /^03/ {print $1}')
if [ ${#NV_BDFS[@]} -eq 0 ]; then
    result "PCIe-Erkennung" FAIL "Keine NVIDIA-Grafikkarte am PCIe-Bus (Stecker? Steckplatz? Karte tot?)"
    lspci -nn >> "$LOG"
    FATAL=1
fi
[ ${#NV_BDFS[@]} -gt 1 ] && say "Hinweis: ${#NV_BDFS[@]} NVIDIA-GPUs gefunden – geprüft wird nur --gpu $GPU. Für eindeutige Ergebnisse nur die Testkarte einbauen."

FATAL=${FATAL:-0}
# Report aus /tmp auf den Stick verschieben (Ordnername mit Kartenname)
move_report() {
    local safe final
    safe=$(echo "$1" | tr -c 'A-Za-z0-9_-' '_' | sed 's/__*/_/g; s/_$//')
    final="$REPORT_ROOT/${STAMP}_${safe}"
    # cp statt mv: exFAT kennt keine Eigentümer -> mv als root warnt "failed to preserve ownership"
    mkdir -p "$final" && cp -r "$DIR"/. "$final"/ && rm -rf "${DIR:?}"/* && DIR="$final" && LOG="$DIR/report.txt"
    rmdir "$TMPDIR_RUN" 2>/dev/null
}
# Karte über eine normale Abfrage suchen (nicht "-i N -L": diese Kombination lehnt der
# echte Treiber 595 ab, im Live-Test 2026-10-23 so gefunden). Kurz nach dem Boot kann
# nvidia-smi noch fehlschlagen -> bis zu 20 s wiederholen. Ausgabe landet im Report.
smi_find_gpu() {
    local out rc i
    for i in 1 2 3 4 5; do
        out=$(nvidia-smi --query-gpu=index,pci.bus_id,name --format=csv,noheader 2>&1); rc=$?
        if [ $rc = 0 ] && echo "$out" | awk -F', *' -v g="$GPU" '$1==g{f=1} END{exit !f}'; then
            echo "$out" >> "$LOG"; return 0
        fi
        sleep 4
    done
    { echo "nvidia-smi --query-gpu=index,pci.bus_id,name -> Exit $rc:"; echo "$out"
      echo "nvidia-smi (ohne Optionen):"; nvidia-smi 2>&1 | head -30; } >> "$LOG"
    return 1
}
if [ $FATAL = 0 ] && ! smi_find_gpu; then
    BDF=${NV_BDFS[0]}
    say "nvidia-smi liefert Karte $GPU nicht. Diagnose:"
    lspci -s "$BDF" -nnk -vv >> "$LOG" 2>&1
    journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'nvidia|nvrm|nouveau|Key was rejected|module verification' | tail -40 | tee -a "$LOG"
    if journalctl -k -b --no-pager 2>/dev/null | grep -qi 'Key was rejected\|module verification failed'; then
        result "Treiber" FAIL "Kernelmodul abgelehnt (Secure Boot). Im BIOS Secure Boot deaktivieren."
    elif journalctl -k -b --no-pager 2>/dev/null | grep -qi 'RmInitAdapter failed\|fallen off the bus'; then
        result "Treiber" FAIL "Karte wird gesehen, aber Initialisierung schlägt fehl (RmInitAdapter) – starker Defektverdacht"
    else
        result "Treiber" FAIL "nvidia-smi sieht die Karte nicht (Details im Report)"
    fi
    FATAL=1
fi

if [ $FATAL = 1 ]; then
    # auch ohne funktionierende Karte den Report sichern (Beleg für den Verkäufer)
    if [ ${#NV_BDFS[@]} -gt 0 ]; then
        move_report "NVIDIA_$(lspci -s "${NV_BDFS[0]}" -n | awk '{print $3}' | tr ':' '-')_ohne_Treiber"
    else
        move_report "KEINE_NVIDIA_KARTE"
    fi
fi
if [ $FATAL = 0 ]; then
    BUSID=$(q1 pci.bus_id)                       # 00000000:01:00.0
    BDF=$(echo "$BUSID" | sed -E 's/^0*([0-9a-fA-F]{4}):/\1:/' | tr 'A-F' 'a-f')
    [ -e "$PCI_SYSFS/$BDF" ] || BDF=$(echo "$BUSID" | tr 'A-F' 'a-f' | sed -E 's/^0000//')
    SYS=$PCI_SYSFS/$BDF
    NAME=$(q1 name)
    VEN=$(cut -c3- "$SYS/vendor");   DEV=$(cut -c3- "$SYS/device")
    SVEN=$(cut -c3- "$SYS/subsystem_vendor"); SDEV=$(cut -c3- "$SYS/subsystem_device")
    SVEN_NAME=$(lspci -s "$BDF" -vmm | awk -F'\t' '/^SVendor:/{print $2}')
    SDEV_NAME=$(lspci -s "$BDF" -vmm | awk -F'\t' '/^SDevice:/{print $2}')
    VBIOS=$(q1 vbios_version)
    VRAM_MIB=$(q1 memory.total)
    SERIAL=$(q1 serial); UUID=$(q1 uuid)
    smi -q > "$DIR/nvidia-smi-q.txt" 2>&1
    ARCH=$(awk -F': ' '/Product Architecture/{print $2; exit}' "$DIR/nvidia-smi-q.txt" | tr -d ' ')
    PARTNO=$(awk -F': ' '/GPU Part Number|Board Part Number/{print $2; exit}' "$DIR/nvidia-smi-q.txt" | sed 's/ *$//')
    PL_DEFAULT=$(q1 power.default_limit); PL_MAX=$(q1 power.max_limit); PL_ENF=$(q1 enforced.power.limit)
    BASE_CLK=$(q1 clocks.default_applications.graphics); MAX_CLK=$(q1 clocks.max.sm)
    # ab Treiber 59x: "[Requested functionality has been deprecated]" -> Referenztabelle
    isnum "$BASE_CLK" || BASE_CLK=$(ref_base_clk "$DEV")
    [ -n "$BASE_CLK" ] || BASE_CLK="?"
    DISP_ACTIVE=$(q1 display_active)

    # VRAM-Typ (für Grenzwerte): GDDR6X bei GA102 3080/3090 + 3070 Ti, Ada 4080/4090/4070 Ti
    case "${DEV,,}" in
        2203|2204|2206|2208|220a|2216|2482|2684|2702|2704|2782|2705) MEMTYPE=GDDR6X ;;
        2b*|2c*|2d*|2f*) MEMTYPE=GDDR7 ;;
        *) MEMTYPE=GDDR6 ;;
    esac
    [ -z "$ARCH" ] && case "${DEV,,}" in 22*|24*|25*) ARCH=Ampere;; 26*|27*|28*) ARCH=Ada;; 2b*|2c*|2d*|2f*) ARCH=Blackwell;; esac
    set_limits "${ARCH:-unknown}" "$MEMTYPE"

    # Report-Ordner jetzt mit Kartenname anlegen
    move_report "$NAME"

    say "  Name           : $NAME   (Architektur: ${ARCH:-?}, VRAM-Typ: $MEMTYPE)"
    say "  PCI-Adresse    : $BDF"
    say "  Vendor/Device  : $VEN:$DEV"
    say "  Subsystem      : $SVEN:$SDEV  ($SVEN_NAME $SDEV_NAME)"
    say "  VBIOS          : $VBIOS"
    say "  VRAM           : $VRAM_MIB MiB"
    say "  Seriennummer   : $SERIAL"
    say "  Part Number    : ${PARTNO:-n/a}"
    say "  UUID           : $UUID"
    say "  Power-Limit    : aktiv $PL_ENF W / default $PL_DEFAULT W / max $PL_MAX W"
    say "  Takt           : Basis $BASE_CLK MHz / max $MAX_CLK MHz"
    lspci -s "$BDF" -nn -vvv > "$DIR/lspci.txt" 2>&1

    [ "$VEN" = 10de ] && result "Identifikation" PASS "$NAME, $VEN:$DEV, Sub $SVEN:$SDEV, VBIOS $VBIOS" \
                      || result "Identifikation" FAIL "Vendor-ID $VEN ist nicht NVIDIA"

    EXP=$(expected_vram_gib "$DEV")
    if [ -n "$EXP" ] && isnum "$VRAM_MIB"; then
        # nvidia-smi zeigt z. B. 24576 MiB (3090) oder 24564 MiB (4090) -> ±3 % Toleranz
        if awk -v m="$VRAM_MIB" -v e="$EXP" 'BEGIN{x=m/1024; exit !(x>=e*0.97 && x<=e*1.03)}'; then
            result "VRAM-Größe" PASS "$VRAM_MIB MiB (erwartet ${EXP} GiB für ID $DEV)"
        else
            result "VRAM-Größe" FAIL "$VRAM_MIB MiB, erwartet ${EXP} GiB für ID $DEV – Fälschung/BIOS-Mod?"
        fi
    else
        result "VRAM-Größe" INFO "$VRAM_MIB MiB (keine Referenz für ID $DEV hinterlegt)"
    fi
    if isnum "$PL_ENF" && isnum "$PL_DEFAULT" && flt "$PL_ENF" "$(echo "$PL_DEFAULT*0.95" | bc)"; then
        result "Power-Limit" WARN "aktiv ${PL_ENF} W < Default ${PL_DEFAULT} W (gedrosselt/BIOS-Mod?)"
    fi
    case "$DISP_ACTIVE" in
        Enabled|Yes) result "Monitor an Karte" PASS "Display wird von dieser Karte ausgegeben" ;;
        *) result "Monitor an Karte" WARN "Kein aktives Display an der Testkarte – Bildausgänge/Artefakte ungetestet" ;;
    esac

    # PCIe-Fähigkeiten: Karte und Steckplatz (Upstream-Bridge)
    GPU_MAXGEN=$(gt2gen "$(cat $SYS/max_link_speed)"); GPU_MAXW=$(cat $SYS/max_link_width)
    BR=$(basename "$(dirname "$(readlink -f $SYS)")")
    if [ -e "$PCI_SYSFS/$BR/max_link_speed" ]; then
        HOST_MAXGEN=$(gt2gen "$(cat $PCI_SYSFS/$BR/max_link_speed)")
        HOST_MAXW=$(cat $PCI_SYSFS/$BR/max_link_width)
    else HOST_MAXGEN=$GPU_MAXGEN; HOST_MAXW=$GPU_MAXW; fi
    WANT_GEN=$(( GPU_MAXGEN < HOST_MAXGEN ? GPU_MAXGEN : HOST_MAXGEN ))
    WANT_W=$(( GPU_MAXW < HOST_MAXW ? GPU_MAXW : HOST_MAXW ))
    say "  PCIe Karte     : max Gen$GPU_MAXGEN x$GPU_MAXW   Steckplatz: max Gen$HOST_MAXGEN x$HOST_MAXW   -> Soll unter Last Gen$WANT_GEN x$WANT_W"
    if [ "$EXP_GEN" -gt 0 ] && [ "$GPU_MAXGEN" != "?" ] && [ "$GPU_MAXGEN" -lt "$EXP_GEN" ]; then
        result "PCIe-Fähigkeit" WARN "Karte meldet max. Gen$GPU_MAXGEN, erwartet Gen$EXP_GEN"
    fi

    # Secure Boot / VRAM-Temperatur-Tool
    SB=$(mokutil --sb-state 2>/dev/null | head -1)
    say "  Secure Boot    : ${SB:-unbekannt};  Kernel-Lockdown: $(cat /sys/kernel/security/lockdown 2>/dev/null || echo n/a)"
    VRAM_NOTE=""
    if [ -x "$GDDR6_BIN" ]; then
        GDDR6_RAW="$TMPDIR_RUN.gddr6.raw"   # Rohstrom nur in /tmp (tmpfs), nicht im Report
        stdbuf -o0 "$GDDR6_BIN" > "$GDDR6_RAW" 2>&1 &
        G6PID=$!; BG_PIDS+=($G6PID); sleep 2
        if [ -z "$(vram_temp_now)" ]; then
            kill $G6PID 2>/dev/null
            if grep -qi 'enabled' <<<"$SB"; then VRAM_NOTE="nicht auslesbar: Secure Boot aktiv (blockiert /dev/mem). Für VRAM-Temp Secure Boot im BIOS abschalten."
            elif grep -q 'No compatible GPU' "$GDDR6_RAW"; then VRAM_NOTE="nicht auslesbar: Karte wird vom gddr6-Tool nicht unterstützt"
            else VRAM_NOTE="nicht auslesbar ($(head -c 120 "$GDDR6_RAW" | tr '\n\r' '  '))"; fi
            GDDR6_RAW=""
        else
            say "  VRAM-Temp      : $(vram_temp_now) °C (gddr6-Tool aktiv)"
        fi
    else
        # gddr6 hat keine Lizenz -> nicht im öffentlichen Image, per Icon nachrüstbar
        VRAM_NOTE="nicht auslesbar: gddr6-Tool nicht installiert (Desktop-Icon „VRAM-Temperatur nachrüsten“, braucht einmal Internet)"
    fi
    # Lüfter-RPM über nvidia-settings möglich?
    if [ -n "${DISPLAY:-}" ] && command -v nvidia-settings >/dev/null; then
        FAN_RPM_OK=1; [ -n "$(fan_rpm_now)" ] || FAN_RPM_OK=0
    fi
    say "  Lüfter-RPM     : $([ $FAN_RPM_OK = 1 ] && echo "auslesbar ($(fan_rpm_now | tr ';' ' ') RPM)" || echo 'nicht auslesbar (nur %-Sollwert)')"
fi

# ===================================================================== Tests ==
CSV="$DIR/monitor.csv"
if [ $FATAL = 0 ]; then
    smi -pm 1 >/dev/null 2>&1   # Persistence Mode (verhindert Treiber-Entladen zwischen Phasen)
    probe_fields

    # ------------------------------------------------------------ 2. Leerlauf
    phase "2. Leerlauf (${T_IDLE}s)"
    start_sampler idle "$DIR/idle.csv"; sleep "$T_IDLE"; stop_sampler
    I_T=$(stat "$DIR/idle.csv" gpu_temp avg); I_P=$(stat "$DIR/idle.csv" power_w avg)
    I_GEN=$(stat "$DIR/idle.csv" pcie_gen mode); I_W=$(stat "$DIR/idle.csv" pcie_width mode)
    I_F=$(stat "$DIR/idle.csv" fan_pct avg)
    say "  GPU ${I_T} °C, ${I_P} W, Lüfter ${I_F} %, PCIe Gen${I_GEN} x${I_W} (Gen-Absenkung im Leerlauf ist normal)"
    if isnum "$I_T"; then
        fge "$I_T" "$LIM_IDLE_WARN" && result "Leerlauf-Temperatur" WARN "${I_T} °C (> ${LIM_IDLE_WARN} °C)" \
                                    || result "Leerlauf-Temperatur" PASS "${I_T} °C"
    fi
    if isnum "$I_P" && isnum "$PL_DEFAULT"; then
        L=$(echo "$PL_DEFAULT*$LIM_IDLE_PWR_PCT/100" | bc)
        fge "$I_P" "$L" && result "Leerlauf-Leistung" WARN "${I_P} W (> ${L} W, evtl. Mining-BIOS/Defekt; bei mehreren Monitoren normal)" \
                        || result "Leerlauf-Leistung" PASS "${I_P} W"
    fi
    if [ "${I_W:-0}" -lt "$WANT_W" ] 2>/dev/null; then
        result "PCIe Leerlauf" WARN "Breite x${I_W} statt x${WANT_W} schon im Leerlauf"
    else
        result "PCIe Leerlauf" INFO "Gen${I_GEN} x${I_W} (Stromsparmodus, Prüfung unter Last)"
    fi

    # ------------------------------------------------------------ 3. VRAM-Test
    if [ $DO_MEMTEST = 1 ] && [ $ABORTED = 0 ]; then
        phase "3. VRAM-Test memtest_vulkan (${T_MEMTEST}s)"
        if [ ! -x "$MEMTEST_BIN" ]; then
            result "VRAM-Test" SKIP "memtest_vulkan nicht gefunden"
        else
            start_sampler memtest "$DIR/memtest.csv"
            # Nur den NVIDIA-Vulkan-Treiber laden (sonst wählt memtest evtl. iGPU/llvmpipe).
            # Argument "1" = erstes Gerät, nicht-interaktiver Modus. SIGTERM beendet sauber
            # (SIGINT wird an Hintergrundjobs nicht-interaktiver Shells ignoriert vererbt).
            # Exit-Code = Status-Bits: 0x40 Signatur | 0x01 Init ok | 0x02 Fehler | 0x04 Abbruch | 0x10 Stop angefordert
            ( cd "$DIR" && VK_DRIVER_FILES="$NV_ICD" VK_ICD_FILENAMES="$NV_ICD" \
                timeout --preserve-status -s TERM -k 30 "$T_MEMTEST" "$MEMTEST_BIN" 1 ) \
                > "$DIR/memtest_vulkan.out" 2>&1 &
            MPID=$!; BG_PIDS+=($MPID)
            while kill -0 $MPID 2>/dev/null; do
                L=$(grep -a 'iteration\|Error' "$DIR/memtest_vulkan.out" | tail -1)
                printf '\r  %s  %s' "$(tail -1 "$DIR/memtest.csv" | awk -F, '{printf "%3.0fs GPU %s°C VRAM %s°C %sW", $1,$3,($17==""?"-":$17),$7}')" "$(echo "$L" | sed -E 's/ +/ /g' | cut -c1-60)"
                sleep 2
            done; echo
            wait $MPID; MRC=$?
            stop_sampler
            cat "$DIR/memtest_vulkan.out" >> "$DIR/memtest_vulkan.full.txt"
            ITER=$(grep -a 'iteration' "$DIR/memtest_vulkan.out" | tail -1 | awk '{print $1}')
            BW=$(grep -a 'iteration' "$DIR/memtest_vulkan.out" | tail -1 | grep -o '[0-9.]*GB/sec' | head -1)   # written, nicht checked
            NERR=$(grep -ac 'Error found' "$DIR/memtest_vulkan.out")
            say "  Exit-Code $MRC (0x$(printf %X $MRC)), Iterationen ${ITER:-0}, Durchsatz ${BW:-?}"
            if [ "$NERR" -gt 0 ] || { [ $((MRC & 0xE0)) -eq 64 ] && [ $((MRC & 0x02)) -ne 0 ]; }; then
                result "VRAM-Test" FAIL "Speicherfehler gefunden ($NERR Meldungen) – VRAM/Speichercontroller defekt"
                grep -a -A6 'Error found' "$DIR/memtest_vulkan.out" | head -40 >> "$LOG"
            elif [ $((MRC & 0xE0)) -ne 64 ] || [ $((MRC & 0x01)) -eq 0 ]; then
                result "VRAM-Test" FAIL "memtest_vulkan konnte nicht laufen/abgestürzt (Exit $MRC) – siehe memtest_vulkan.out"
            elif [ $((MRC & 0x04)) -ne 0 ]; then
                result "VRAM-Test" FAIL "Laufzeitfehler während des Tests (Treiber/Hardware), siehe Xid-Prüfung"
            elif [ "${ITER:-0}" -lt 5 ]; then
                result "VRAM-Test" WARN "nur ${ITER:-0} Iterationen – Test zu kurz/zu langsam"
            else
                result "VRAM-Test" PASS "keine Fehler, $ITER Iterationen, ${BW:-?} in ${T_MEMTEST} s"
            fi
        fi
    fi

    # ------------------------------------------------------------ 4. CUDA-Volllast
    if [ $DO_BURN = 1 ] && [ $ABORTED = 0 ]; then
        phase "4. CUDA-Volllast gpu-burn (${T_BURN}s)"
        if [ ! -x "$GPUBURN_DIR/gpu_burn" ]; then
            result "CUDA-Last" SKIP "gpu_burn nicht gefunden"
        else
            start_sampler burn "$DIR/burn.csv"
            ( cd "$GPUBURN_DIR" && CUDA_DEVICE_ORDER=PCI_BUS_ID ./gpu_burn -i "$GPU" -m 90% -c "$GPUBURN_DIR/compare.fatbin" "$T_BURN" ) \
                > "$DIR/gpu_burn.out" 2>&1 &
            BPID=$!; BG_PIDS+=($BPID)
            MID_DONE=0
            while kill -0 $BPID 2>/dev/null; do
                printf '\r  %s' "$(tail -1 "$DIR/burn.csv" | awk -F, '{printf "%4.0fs  GPU %s°C  VRAM %s°C  %s MHz  %s W  Lüfter %s%%  PCIe Gen%s x%s  [%s]   ", $1,$3,($17==""?"-":$17),$5,$7,$9,$11,$12,$13}')"
                # Stichprobe Link per sysfs zur Mitte der Last
                if [ $MID_DONE = 0 ] && [ "$(tail -1 "$DIR/burn.csv" | cut -d, -f1 | cut -d. -f1)" -ge $((T_BURN/2)) ] 2>/dev/null; then
                    SYS_LOAD_LINK="$(cat $SYS/current_link_speed) x$(cat $SYS/current_link_width)"; MID_DONE=1
                fi
                sleep 2
            done; echo
            wait $BPID; BRC=$?
            stop_sampler
            tr '\r' '\n' < "$DIR/gpu_burn.out" | grep -v '^\s*$' | tail -15 >> "$LOG"
            if grep -q 'GPU [0-9]*: OK' "$DIR/gpu_burn.out"; then
                result "CUDA-Rechenfehler" PASS "gpu-burn: keine Rechenfehler"
            elif grep -q 'FAULTY' "$DIR/gpu_burn.out"; then
                result "CUDA-Rechenfehler" FAIL "gpu-burn meldet FAULTY (falsche Rechenergebnisse!)"
            else
                result "CUDA-Rechenfehler" FAIL "gpu-burn ohne Ergebnis (Exit $BRC, Absturz?) – siehe gpu_burn.out"
            fi
        fi
    fi

    # ------------------------------------------------------------ 5. Vulkan-Grafiklast
    if [ $DO_GL = 1 ] && [ $ABORTED = 0 ]; then
        phase "5. Vulkan-Grafiklast vkmark (${T_GL}s)"
        if [ -z "${DISPLAY:-}" ]; then
            result "Grafiklast" SKIP "keine grafische Sitzung (DISPLAY fehlt)"
        else
            say "  >>> Bitte auf den Bildschirm schauen: Flackern, bunte Punkte/Streifen, Schachbrett = Defekt <<<"
            start_sampler gl "$DIR/gl.csv"
            XA=${XAUTHORITY:-/home/$DESKTOP_USER/.Xauthority}
            # vkmark: Szenen in Endlosschleife (--run-forever), Vollbild, bis Zeitablauf.
            # immediate = ungebremst (maximale Last statt 60-fps-VSync)
            GL_T0=$SECONDS
            runuser -u "$DESKTOP_USER" -- env DISPLAY="$DISPLAY" XAUTHORITY="$XA" VK_DRIVER_FILES="$NV_ICD" \
                timeout --preserve-status -s TERM -k 10 "$T_GL" \
                vkmark --winsys xcb --fullscreen --present-mode immediate --run-forever \
                    -b vertex:duration=8 -b texture:duration=8 -b shading:shading=phong:duration=8 \
                    -b cube:duration=8 -b effect2d:duration=8 -b desktop:duration=8 \
                > "$DIR/vkmark.out" 2>&1
            GRC=$?; GL_DUR=$((SECONDS - GL_T0))
            stop_sampler
            grep -E 'FPS|Score' "$DIR/vkmark.out" | tail -10 >> "$LOG"
            echo "  vkmark Exit-Code $GRC nach ${GL_DUR}s" >> "$LOG"
            # vkmark 2025.01 fängt SIGTERM ab, gibt den Score aus und endet mit 0 (ältere: 143).
            # OK = Exit 0/143 UND bis zum Zeitablauf gelaufen; sonst vorher beendet/abgestürzt.
            if [ $GRC = 0 ] || [ $GRC = 143 ]; then [ $GL_DUR -ge $((T_GL - 2)) ] || GRC=-1; fi
            if grep -qiE 'connect to X server|cannot open display' "$DIR/vkmark.out"; then
                result "Grafiklast" SKIP "vkmark kann keine Verbindung zum Desktop herstellen (Testaufbau, kein Kartendefekt)"
            elif { [ $GRC != 0 ] && [ $GRC != 143 ]; } || grep -qiE 'error|failed|segmentation|abort' "$DIR/vkmark.out"; then
                result "Grafiklast" FAIL "vkmark abgebrochen/Fehler – siehe vkmark.out"
            else
                GL_FPS=$(grep -o 'FPS: [0-9]*' "$DIR/vkmark.out" | awk '{s+=$2;n++} END{if(n) printf "%d Szenen, Ø %.0f FPS", n, s/n}')
                result "Grafiklast" PASS "vkmark ${T_GL}s ohne Absturz${GL_FPS:+, $GL_FPS}"
            fi
            if [ $ASK = 1 ] && [ $ABORTED = 0 ] && [ "${R_STATE[-1]}" != SKIP ]; then
                printf '\a'
                read -r -t 120 -p "  Waren Bildfehler zu sehen (Artefakte, Flackern, Blackscreen)? [j/N] " ANS
                case "${ANS:-n}" in
                    j*|J*|y*|Y*) result "Bildfehler (Sicht)" FAIL "vom Tester beobachtet" ;;
                    *) result "Bildfehler (Sicht)" PASS "keine beobachtet" ;;
                esac
            fi
        fi
    fi

    # ------------------------------------------------------------ 6. Auswertung Messwerte
    phase "6. Auswertung Temperatur / Takt / Leistung / Lüfter / PCIe"
    # Lastphasen zusammenfassen (CUDA ist die Referenz für Takt/Leistung)
    cat "$DIR"/idle.csv > "$CSV"
    for p in memtest burn gl; do [ -f "$DIR/$p.csv" ] && tail -n +2 "$DIR/$p.csv" >> "$CSV"; done

    LOAD="$DIR/burn.csv"; WARM=30      # erste 30 s Aufheizen ignorieren
    [ -f "$LOAD" ] || { LOAD="$DIR/memtest.csv"; WARM=20; }
    [ "$T_BURN" -lt 90 ] && WARM=10
    LOADN=$(basename "$LOAD")
    # Nur Messpunkte mit echter Last auswerten: der Sampler läuft nach Lastende noch
    # ~20–30 s weiter (gpu_burn beendet sich), Leerlaufwerte verfälschen sonst Ø Leistung/Takt/Lüfter.
    if [ -f "$LOAD" ]; then
        awk -F, 'NR==1 { for (i=1;i<=NF;i++) if ($i=="util_pct") c=i; print; next }
                 c && $c+0 >= 50' "$LOAD" > "$DIR/load_active.csv"
        [ "$(wc -l < "$DIR/load_active.csv")" -gt 5 ] && LOAD="$DIR/load_active.csv"
    fi
    if [ -f "$LOAD" ]; then
        T_MAX=$(stat "$LOAD" gpu_temp max); T_AVG=$(stat "$LOAD" gpu_temp avg "$WARM")
        P_AVG=$(stat "$LOAD" power_w avg "$WARM"); P_MAX=$(stat "$LOAD" power_w max)
        PL=$(stat "$LOAD" power_limit_w avg)
        C_AVG=$(stat "$LOAD" sm_clk avg "$WARM"); C_MIN=$(stat "$LOAD" sm_clk min "$WARM")
        F_AVG=$(stat "$LOAD" fan_pct avg "$WARM"); F_MAX=$(stat "$LOAD" fan_pct max)
        L_GEN=$(stat "$LOAD" pcie_gen mode "$WARM"); L_W=$(stat "$LOAD" pcie_width mode "$WARM")
        U_AVG=$(stat "$LOAD" util_pct avg "$WARM")
        say "  Last-Referenz: ${LOADN%.csv}  (Auslastung Ø ${U_AVG} %)"
        say "  GPU-Temp max ${T_MAX} °C / Ø ${T_AVG} °C | SM-Takt Ø ${C_AVG} MHz (min ${C_MIN}) | Leistung Ø ${P_AVG} W (max ${P_MAX}, Limit ${PL}) | Lüfter Ø ${F_AVG} %"

        # --- Kerntemperatur (Maximum über alle Lastphasen)
        T_ALL=$(stat "$CSV" gpu_temp max)
        if isnum "$T_ALL"; then
            if fge "$T_ALL" "$LIM_CORE_FAIL"; then result "GPU-Temperatur" FAIL "max ${T_ALL} °C (>= ${LIM_CORE_FAIL} °C) – Kühlung/Paste prüfen"
            elif fge "$T_ALL" "$LIM_CORE_WARN"; then result "GPU-Temperatur" WARN "max ${T_ALL} °C (>= ${LIM_CORE_WARN} °C)"
            else result "GPU-Temperatur" PASS "max ${T_ALL} °C"; fi
        fi
        # --- T.Limit (Reserve bis Slowdown)
        if [ $HAVE_TLIMIT = 1 ]; then
            TL_MIN=$(stat "$CSV" tlimit min)
            if isnum "$TL_MIN"; then
                flt "$TL_MIN" "$LIM_TLIMIT_WARN" && result "Temp.-Reserve (T.Limit)" WARN "nur ${TL_MIN} °C bis Slowdown" \
                                                 || result "Temp.-Reserve (T.Limit)" PASS "min. ${TL_MIN} °C bis Slowdown"
            fi
        fi
        # --- Hotspot: wird von NVML für GeForce nicht bereitgestellt
        result "Hotspot-Temperatur" INFO "unter Linux nicht auslesbar (NVIDIA stellt Hotspot für GeForce nicht über NVML bereit)"
        # --- VRAM-Temperatur
        V_MAX=$(stat "$CSV" vram_temp max); V_NVML=$(stat "$CSV" mem_temp_nvml max)
        isnum "$V_MAX" || V_MAX=$V_NVML
        if isnum "$V_MAX"; then
            if fge "$V_MAX" "$LIM_VRAM_FAIL"; then result "VRAM-Temperatur" FAIL "max ${V_MAX} °C (>= ${LIM_VRAM_FAIL} °C) – Wärmeleitpads verschlissen?"
            elif fge "$V_MAX" "$LIM_VRAM_WARN"; then result "VRAM-Temperatur" WARN "max ${V_MAX} °C (>= ${LIM_VRAM_WARN} °C)"
            else result "VRAM-Temperatur" PASS "max ${V_MAX} °C ($MEMTYPE, Grenze WARN ${LIM_VRAM_WARN})"; fi
        else
            result "VRAM-Temperatur" SKIP "${VRAM_NOTE:-nicht auslesbar}"
        fi

        # --- Throttle-Gründe (NVML clocks_event_reasons Bits)
        S_PWR=$(throttle_pct "$LOAD" 4 "$WARM")       # 0x04 SW Power Cap
        S_HWS=$(throttle_pct "$LOAD" 8 "$WARM")       # 0x08 HW Slowdown
        S_SWT=$(throttle_pct "$LOAD" 32 "$WARM")      # 0x20 SW Thermal Slowdown
        S_HWT=$(throttle_pct "$LOAD" 64 "$WARM")      # 0x40 HW Thermal Slowdown
        S_HPB=$(throttle_pct "$LOAD" 128 "$WARM")     # 0x80 HW Power Brake
        say "  Throttle-Anteile: PowerCap ${S_PWR}%  SW-Thermal ${S_SWT}%  HW-Slowdown ${S_HWS}%  HW-Thermal ${S_HWT}%  HW-PowerBrake ${S_HPB}%"
        TH_STATE=PASS; TH_MSG="nur Power-Limit (normal unter Volllast)"
        flt 0 "$S_SWT" && { TH_STATE=PASS; TH_MSG="SW-Thermal ${S_SWT}% (leicht)"; }
        fge "$S_SWT" "$LIM_SWTHERM_WARN_PCT" && { TH_STATE=WARN; TH_MSG="SW-Thermal-Drosselung ${S_SWT}% der Zeit"; }
        HW_LIST=""
        for pair in "HW-Slowdown:$S_HWS" "HW-Thermal:$S_HWT" "HW-PowerBrake:$S_HPB"; do
            n=${pair%%:*}; v=${pair#*:}
            if fge "$v" "$LIM_HW_FAIL_PCT"; then TH_STATE=FAIL; HW_LIST+="${HW_LIST:+, }$n ${v}%"
            elif flt 0 "$v" && [ $TH_STATE != FAIL ]; then TH_STATE=WARN; TH_MSG="$n vereinzelt (${v}%)"; fi
        done
        [ -n "$HW_LIST" ] && TH_MSG="$HW_LIST – Stromversorgung/12V-Stecker/VRM oder Überhitzung"
        result "Throttle-Gründe" "$TH_STATE" "$TH_MSG"

        # --- Leistung (nur wenn CUDA-Last gelaufen ist; memtest zieht kein Power-Limit)
        if [ "$LOADN" = burn.csv ] && isnum "$P_AVG" && isnum "$PL"; then
            PCT=$(awk -v a="$P_AVG" -v b="$PL" 'BEGIN{printf "%.0f", 100*a/b}')
            if flt "$PCT" "$LIM_PWR_FAIL_PCT" && ! fge "$S_SWT" 10; then result "Leistungsaufnahme" FAIL "Ø ${P_AVG} W = ${PCT}% des Limits ${PL} W – Karte zieht keine Volllast"
            elif flt "$PCT" "$LIM_PWR_WARN_PCT"; then result "Leistungsaufnahme" WARN "Ø ${P_AVG} W = ${PCT}% des Limits ${PL} W"
            else result "Leistungsaufnahme" PASS "Ø ${P_AVG} W = ${PCT}% des Limits ${PL} W"; fi
        fi
        # --- Takt
        if [ "$LOADN" = burn.csv ] && isnum "$C_AVG" && isnum "$BASE_CLK" && [ "${BASE_CLK%.*}" -gt 0 ]; then
            PCT=$(awk -v a="$C_AVG" -v b="$BASE_CLK" 'BEGIN{printf "%.0f", 100*a/b}')
            if flt "$PCT" "$LIM_CLK_FAIL_PCT"; then result "Takt unter Last" FAIL "Ø ${C_AVG} MHz = ${PCT}% des Basistakts ${BASE_CLK} MHz"
            elif flt "$PCT" "$LIM_CLK_WARN_PCT"; then result "Takt unter Last" WARN "Ø ${C_AVG} MHz unter Basistakt ${BASE_CLK} MHz"
            else result "Takt unter Last" PASS "Ø ${C_AVG} MHz (Basis ${BASE_CLK}, max ${MAX_CLK})"; fi
        fi
        # --- Lüfter
        RPM_MIN=$(fan_rpm_min "$LOAD" "$WARM"); NF=$(num_fans "$LOAD"); FAN_DEAD=$(fan_dead_pct "$LOAD" "$WARM")
        if [ "$FAN_DEAD" -ge 50 ]; then
            result "Lüfter" FAIL "ein Lüfter steht (0 RPM), während die anderen drehen – Lüfter defekt/Kabel lose"
        elif isnum "$RPM_MIN" && [ "$RPM_MIN" -eq 0 ] && isnum "$F_AVG" && fge "$F_AVG" "$LIM_FAN_MIN_PCT"; then
            result "Lüfter" FAIL "ein Lüfter steht unter Last (0 RPM bei Soll ${F_AVG} %) – Lüfter defekt/Kabel lose"
        elif isnum "$T_MAX" && fge "$T_MAX" 65 && isnum "$F_MAX" && flt "$F_MAX" "$LIM_FAN_MIN_PCT"; then
            result "Lüfter" WARN "nur ${F_MAX} % bei ${T_MAX} °C – Lüfterkurve/Lüfter prüfen"
        else
            result "Lüfter" PASS "Ø ${F_AVG} % unter Last$(isnum "$RPM_MIN" && echo ", $NF Lüfter, min ${RPM_MIN} RPM")"
        fi
        # --- PCIe unter Last
        say "  PCIe unter Last: nvidia-smi Gen${L_GEN} x${L_W}; sysfs-Stichprobe: ${SYS_LOAD_LINK:-n/a}"
        if [ -n "$L_GEN" ] && [ "$L_GEN" -lt "$WANT_GEN" ] 2>/dev/null; then
            result "PCIe-Link Last" WARN "Gen${L_GEN} x${L_W}, möglich wäre Gen${WANT_GEN} x${WANT_W} (Riser/Steckplatz/BIOS-Einstellung?)"
        elif [ -n "$L_W" ] && [ "$L_W" -lt "$WANT_W" ] 2>/dev/null; then
            result "PCIe-Link Last" WARN "Breite x${L_W} statt x${WANT_W} – Kontakte verschmutzt/beschädigt oder Steckplatz"
        else
            result "PCIe-Link Last" PASS "Gen${L_GEN} x${L_W}"
        fi
    fi
fi

# ===================================================================== 7. Kernel-Log
phase "7. Kernel-Log (Xid / PCIe-AER)"
journalctl -k -b --no-pager -o short-iso > "$DIR/kernel.log" 2>/dev/null || dmesg -T > "$DIR/kernel.log"
XID_ALL=$(grep -c 'NVRM: Xid' "$DIR/kernel.log")
XID_RUN=$(journalctl -k -b --no-pager --since "@$START_EPOCH" 2>/dev/null | grep 'NVRM: Xid')
XID_RUN_N=$(printf '%s' "$XID_RUN" | grep -c 'Xid' )
AER_UNC=$(grep -ciE 'AER:.*(Uncorrect|Fatal)' "$DIR/kernel.log")
AER_COR=$(grep -ciE 'AER:.*Corrected' "$DIR/kernel.log")
OFFBUS=$(grep -ci 'fallen off the bus' "$DIR/kernel.log")
grep -E 'NVRM: Xid|AER:|fallen off' "$DIR/kernel.log" | tail -30 >> "$LOG"
if [ "$OFFBUS" -gt 0 ]; then result "Xid-Fehler" FAIL "GPU ist vom Bus gefallen (Xid 79) – Stromversorgung/Defekt"
elif [ "$XID_RUN_N" -gt 0 ]; then result "Xid-Fehler" FAIL "$XID_RUN_N Xid während des Tests: $(echo "$XID_RUN" | grep -o 'Xid ([^)]*): [0-9]*' | awk '{print $NF}' | sort -u | paste -sd,)"
elif [ "$XID_ALL" -gt 0 ]; then result "Xid-Fehler" WARN "$XID_ALL Xid seit Boot, aber nicht während des Tests"
else result "Xid-Fehler" PASS "keine Xid-Meldungen"; fi
if [ "$AER_UNC" -gt 0 ]; then result "PCIe-Fehler (AER)" FAIL "$AER_UNC nicht korrigierbare PCIe-Fehler"
elif [ "$AER_COR" -gt 10 ]; then result "PCIe-Fehler (AER)" WARN "$AER_COR korrigierte PCIe-Fehler (Kontakte/Riser/Steckplatz)"
else result "PCIe-Fehler (AER)" PASS "keine relevanten PCIe-Fehler ($AER_COR korrigiert)"; fi

# ===================================================================== Zusammenfassung
OVERALL=PASS
for s in "${R_STATE[@]}"; do
    [ "$s" = FAIL ] && OVERALL=FAIL
    [ "$s" = WARN ] && [ $OVERALL = PASS ] && OVERALL=WARN
done
[ $ABORTED = 1 ] && [ $OVERALL = PASS ] && OVERALL=WARN
END_ISO=$(date '+%Y-%m-%d %H:%M:%S'); DUR=$(( $(date +%s) - START_EPOCH ))

{
    echo
    echo "=================================================================="
    echo " ZUSAMMENFASSUNG   ${NAME:-unbekannte Karte}"
    echo " $START_ISO – $END_ISO  (Dauer $((DUR/60)) Min. $((DUR%60)) s, Modus $MODE$([ $ABORTED = 1 ] && echo ', ABGEBROCHEN'))"
    echo "=================================================================="
    for i in "${!R_NAME[@]}"; do printf ' %-5s %s %s\n' "${R_STATE[$i]}" "$(pad "${R_NAME[$i]}" 24)" "${R_MSG[$i]}"; done
    echo "------------------------------------------------------------------"
    echo " GESAMT: $OVERALL"
    case $OVERALL in
        PASS) echo " Keine Auffälligkeiten in den durchgeführten Tests." ;;
        WARN) echo " Auffälligkeiten – WARN-Punkte oben ansehen und abwägen (Preis verhandeln?)." ;;
        FAIL) echo " Mindestens ein harter Fehler – vom Kauf wird abgeraten." ;;
    esac
    echo " Report: $DIR"
    echo "=================================================================="
} > "$DIR/summary.txt"
cat "$DIR/summary.txt" >> "$LOG"
echo
case $OVERALL in PASS) c=$C_G;; WARN) c=$C_Y;; *) c=$C_R;; esac
sed -E "s/^ (PASS) /${C_G} \1${C_0} /; s/^ (WARN) /${C_Y} \1${C_0} /; s/^ (FAIL) /${C_R} \1${C_0} /; s/GESAMT: (.*)/GESAMT: ${c}\1${C_0}/" "$DIR/summary.txt"

chmod -R a+rwX "$DIR" 2>/dev/null
sync
if [ -n "${DISPLAY:-}" ] && command -v zenity >/dev/null; then
    runuser -u "$DESKTOP_USER" -- env DISPLAY="$DISPLAY" XAUTHORITY="${XAUTHORITY:-/home/$DESKTOP_USER/.Xauthority}" \
        zenity --text-info --title="GPU-Check: $OVERALL" --filename="$DIR/summary.txt" --width=900 --height=600 \
        --font="DejaVu Sans Mono 10" >/dev/null 2>&1 &
fi
[ $OVERALL = FAIL ] && exit 1 || exit 0
