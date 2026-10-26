#!/bin/bash
# Stage 2 (im chroot): memtest_vulkan, gddr6, gpu-burn. Build-Tools werden danach entfernt.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
DL=/root/build/dl
CUDA_VER=13-4
CUDA_DIR=/usr/local/cuda-13.4
G=/opt/gpucheck
mkdir -p $G/bin $G/gpu-burn/lib $G/src

apt-get -y install xz-utils
# --- memtest_vulkan (Prebuilt, SHA256 vorher geprüft)
tar -xJf $DL/memtest/memtest_vulkan-v0.5.0_DesktopLinux_X86_64.tar.xz -C $G/bin
chmod 755 $G/bin/memtest_vulkan

# --- Build-Abhängigkeiten (werden am Ende wieder entfernt)
BUILD_PKGS="build-essential cmake pkg-config libpci-dev patchelf"
apt-get -y install $BUILD_PKGS
dpkg -i $DL/cuda/cuda-keyring_1.1-1_all.deb
apt-get update
apt-get -y install cuda-nvcc-$CUDA_VER cuda-cudart-dev-$CUDA_VER libcublas-dev-$CUDA_VER cuda-cuobjdump-$CUDA_VER

# --- gddr6 (VRAM-Temperatur)
B=$(mktemp -d /root/build/work.XXXX); tar -xzf $DL/gddr6/src-*.tar.gz -C $B --strip-components=1
cmake -S $B -B $B/build -DCMAKE_BUILD_TYPE=Release
cmake --build $B/build -j"$(nproc)"
install -m755 "$(find $B/build -type f -name gddr6 -perm -u+x | head -1)" $G/bin/gddr6
cp $DL/gddr6/src-*.tar.gz $G/src/

# --- gpu-burn (CUDA 13): nativer Code für Ampere (sm_86), Ada (sm_89), Blackwell (sm_120),
#     dazu PTX compute_75 als JIT-Fallback für künftige GPUs. cuBLAS 13 enthält Blackwell-Kernel.
B=$(mktemp -d /root/build/work.XXXX); tar -xzf $DL/gpuburn/src-*.tar.gz -C $B --strip-components=1
make -C $B CUDAPATH=$CUDA_DIR COMPUTE= NVCCFLAGS="-gencode arch=compute_86,code=sm_86 -gencode arch=compute_89,code=sm_89 -gencode arch=compute_120,code=sm_120 -gencode arch=compute_75,code=compute_75"
install -m755 $B/gpu_burn $G/gpu-burn/gpu_burn
install -m644 $B/compare.fatbin $G/gpu-burn/compare.fatbin
$CUDA_DIR/bin/cuobjdump --list-elf --list-ptx $G/gpu-burn/compare.fatbin
# benötigte CUDA-Laufzeitbibliotheken mitnehmen, dann Toolkit entfernen
for l in libcudart.so.13 libcublas.so.13 libcublasLt.so.13; do
    cp -L $CUDA_DIR/targets/x86_64-linux/lib/$l $G/gpu-burn/lib/
done
patchelf --set-rpath '$ORIGIN/lib' $G/gpu-burn/gpu_burn
cp $DL/gpuburn/src-*.tar.gz $G/src/
echo "--- ldd gpu_burn"; ldd $G/gpu-burn/gpu_burn

# --- aufräumen: CUDA-Toolkit, NVIDIA-Repo, Build-Tools
apt-get -y purge 'cuda-*' 'libcublas*' 'libnpp*' 'libcufft*' 'libcurand*' 'libcusolver*' 'libcusparse*' 'libnvjitlink*' cuda-keyring || true
apt-get -y purge $BUILD_PKGS || true
apt-get -y autoremove --purge
unlink /etc/apt/sources.list.d/cuda-ubuntu2604-x86_64.list 2>/dev/null || true
apt-get update
apt-get clean

echo "--- ldd gpu_burn nach Purge"; ldd $G/gpu-burn/gpu_burn
ldd $G/bin/gddr6
echo "STAGE2 OK"
