#!/bin/sh
# Erzeugt ein simuliertes PCI-sysfs (RTX 3090 an PCIe-4.0-x16-Port) für die Mock-Tests.
# Liegt nicht im Repository, weil Dateinamen mit ":" unter Windows nicht gehen.
#   PCI_SYSFS=$(./mk-sys.sh /tmp/gpucheck-mock-sys)
set -e
D=${1:-/tmp/gpucheck-mock-sys}
P=$D/devices/pci0000:00/0000:00:01.0; G=$P/0000:01:00.0
mkdir -p "$G" "$D/bus/pci/devices"
echo 16 > "$P/max_link_width"; echo "16.0 GT/s PCIe" > "$P/max_link_speed"
for f in current max; do echo 16 > "$G/${f}_link_width"; echo "16.0 GT/s PCIe" > "$G/${f}_link_speed"; done
echo 0x10de > "$G/vendor"; echo 0x2204 > "$G/device"
echo 0x1043 > "$G/subsystem_vendor"; echo 0x87b3 > "$G/subsystem_device"
ln -sfn ../../../devices/pci0000:00/0000:00:01.0 "$D/bus/pci/devices/0000:00:01.0"
ln -sfn ../../../devices/pci0000:00/0000:00:01.0/0000:01:00.0 "$D/bus/pci/devices/0000:01:00.0"
echo "$D/bus/pci/devices"
