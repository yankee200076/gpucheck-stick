#!/bin/bash
# VM-Test des Sticks: QEMU + OVMF, Stick read-only per snapshot=on (keine Schreibzugriffe auf /dev/sda).
#   vmtest.sh start sb|nosb     VM starten (Hintergrund)
#   vmtest.sh shot NAME         Screenshot -> NAME.png
#   vmtest.sh cmd "MONITOR-CMD" HMP-Befehl (sendkey, mouse_move, ...)
#   vmtest.sh stop
set -euo pipefail
W=${VM_DIR:-/tmp/gpucheck-vm}
mkdir -p "$W"
SOCK=$W/mon.sock
hmp() { python3 -I - "$SOCK" "$1" <<'EOF'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.settimeout(3)
def rd():
    b = b""
    try:
        while not b.endswith(b"(qemu) "):
            c = s.recv(65536)
            if not c: break          # Verbindung zu (z. B. nach quit)
            b += c
    except socket.timeout: pass
    return b
rd(); s.sendall(sys.argv[2].encode() + b"\n"); out = rd()
print(out.decode(errors="replace").replace("(qemu) ", "").strip())
EOF
}
case $1 in
start)
    [ "$(lsblk -dno SERIAL /dev/sda)" = "${STICK_SERIAL:?}" ] || { echo "falscher Stick"; exit 1; }
    if [ "$2" = sb ]; then CODE=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd; VARS=/usr/share/OVMF/OVMF_VARS_4M.ms.fd
    else CODE=/usr/share/OVMF/OVMF_CODE_4M.fd; VARS=/usr/share/OVMF/OVMF_VARS_4M.fd; fi
    cp "$VARS" "$W/vars-$2.fd"
    qemu-system-x86_64 -enable-kvm -machine q35,smm=on -cpu host -smp 2 -m 2048 \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive if=pflash,format=raw,unit=0,file="$CODE",readonly=on \
        -drive if=pflash,format=raw,unit=1,file="$W/vars-$2.fd" \
        -drive file=/dev/sda,format=raw,if=none,id=usb0,snapshot=on,cache=unsafe \
        -device qemu-xhci -device usb-storage,drive=usb0,bootindex=0 \
        -device usb-tablet -vga std -display none -nic none \
        -monitor unix:"$SOCK",server,nowait -serial file:"$W/serial-$2.log" \
        -daemonize -pidfile "$W/qemu.pid"
    echo "VM gestartet ($2)";;
shot)
    hmp "screendump $W/$2.ppm" >/dev/null; sleep 1
    python3 -I -c "from PIL import Image; Image.open('$W/$2.ppm').save('$W/$2.png')"; echo "$W/$2.png";;
cmd) hmp "$2";;
stop) hmp quit >/dev/null 2>&1 || true; sleep 1; [ -f "$W/qemu.pid" ] && kill "$(cat "$W/qemu.pid")" 2>/dev/null || true; echo gestoppt;;
esac
