#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Smoke-boot the J773g Omarchy image in QEMU (generic virt machine, TCG inside
# the Arch Linux ARM container): proves the root filesystem, the kernel package
# and systemd, not the Mac hardware. docs/j773g-image.md.
#
#   tools/j773g-image-smoke.sh [seconds]   boot build/j773g/image/{root,boot}.img,
#                                          serial console to build/j773g/smoke/console.log,
#                                          stop after <seconds> (default 420)
#
# Login is not possible (owner provisioning has not run); the check is that
# systemd reaches multi-user.target and the first-boot units start. The images
# in build/j773g/image/ are copied first and never modified.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
IMG=$REPO/build/j773g/image
WORK=$REPO/build/j773g/smoke
KERNEL=linux-gravity-m4
LIMIT=${1:-420}
mkdir -p "$WORK"
[[ -f $IMG/root.img && -f $IMG/boot.img ]] || { echo "no image in $IMG; run tools/j773g-image.sh first" >&2; exit 1; }

docker run --rm --platform linux/arm64 --privileged -v "$IMG:/img:ro" -v "$WORK:/w" --user root omarchy-j773g-alarm bash -c "
  set -euo pipefail
  pacman -Sy --noconfirm --needed qemu-system-aarch64 >/dev/null
  # Kernel and fallback initramfs (every module; the autodetected one may lack
  # virtio) out of the ext4 boot image.
  debugfs -R 'dump /vmlinuz-$KERNEL /w/vmlinuz' /img/boot.img
  # The Mac preset builds no fallback image; the normal one carries every block
  # driver (the chroot build autodetected nothing).
  debugfs -R 'dump /initramfs-$KERNEL-fallback.img /w/initramfs.img' /img/boot.img 2>/dev/null
  [[ -s /w/initramfs.img ]] || debugfs -R 'dump /initramfs-$KERNEL.img /w/initramfs.img' /img/boot.img
  cp -f /img/root.img /w/root.img; cp -f /img/boot.img /w/boot.img
  mkdir -p /m && mount -o loop,ro,subvol=@ /w/root.img /m
  uuid=\$(sed -n 's/^UUID=\([^ ]*\) *\/ .*/\1/p' /m/etc/fstab); umount /m
  echo \"root UUID \$uuid; booting for $LIMIT s (console -> build/j773g/smoke/console.log)\"
  timeout --foreground $LIMIT qemu-system-aarch64 -M virt -accel tcg,thread=multi -cpu max -smp 4 -m 4096 -nographic \
    -kernel /w/vmlinuz -initrd /w/initramfs.img \
    -append \"root=UUID=\$uuid rootflags=subvol=@ rw console=ttyAMA0 loglevel=5 systemd.unit=multi-user.target\" \
    -drive if=none,file=/w/root.img,format=raw,id=root -device virtio-blk-pci,drive=root \
    -drive if=none,file=/w/boot.img,format=raw,id=boot -device virtio-blk-pci,drive=boot \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 -device virtio-rng-pci 2>&1 | tee /w/console.log || true
  echo; echo '== verdict'
  grep -E 'Reached target .*Multi-User|Welcome to|omarchy-mac-first-boot|omarchy-provision|Failed to start|Kernel panic|login:' /w/console.log | head -20"
