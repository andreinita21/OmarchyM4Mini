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
# in build/j773g/image/ are copied into a scratch GPT disk and never modified.
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
  # One GPT disk as the installer lays it out (ESP, Boot, Root), so the Mac
  # boot hooks see partitions: the ESP with volume id 4F4D-5801 and the esp/
  # tree, then boot.img and root.img copied in at their partition offsets.
  root_mib=\$(( ( \$(stat -c %s /img/root.img) + 1048575 ) / 1048576 ))
  rm -f /w/disk.img; truncate -s \$(( (1 + 500 + 2048 + root_mib + 2) * 1048576 )) /w/disk.img
  printf 'label: gpt\nunit: MiB\nstart=1, size=500, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=EFI\nstart=501, size=2048, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=Boot\nstart=2549, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=Root\n' | sfdisk -q /w/disk.img
  rm -f /w/esp.img; truncate -s 524288000 /w/esp.img
  mkfs.vfat -F 32 -n OMARCHYESP -i 4f4d5801 /w/esp.img >/dev/null
  mcopy -i /w/esp.img -s -p /img/esp/* ::/
  dd if=/w/esp.img of=/w/disk.img bs=1M seek=1 conv=notrunc,sparse status=none
  dd if=/img/boot.img of=/w/disk.img bs=1M seek=501 conv=notrunc,sparse status=none
  dd if=/img/root.img of=/w/disk.img bs=1M seek=2549 conv=notrunc,sparse status=none
  rm -f /w/esp.img
  mkdir -p /m && mount -o loop,ro,subvol=@ /img/root.img /m
  uuid=\$(sed -n 's/^UUID=\([^ ]*\) *\/ .*/\1/p' /m/etc/fstab); umount /m
  echo \"root UUID \$uuid; booting for $LIMIT s (console -> build/j773g/smoke/console.log)\"
  timeout --foreground $LIMIT qemu-system-aarch64 -M virt -accel tcg,thread=multi -cpu max -smp 4 -m 4096 -nographic \
    -kernel /w/vmlinuz -initrd /w/initramfs.img \
    -append \"root=UUID=\$uuid rootflags=subvol=@ rw console=ttyAMA0 loglevel=5 systemd.unit=multi-user.target\" \
    -drive if=none,file=/w/disk.img,format=raw,id=disk -device virtio-blk-device,drive=disk \
    -netdev user,id=n0 -device virtio-net-device,netdev=n0 -device virtio-rng-device 2>&1 | tee /w/console.log || true
  echo; echo '== verdict'
  grep -E 'Reached target .*Multi-User|Welcome to|omarchy-mac-first-boot|omarchy-provision|Failed to start|Kernel panic|login:' /w/console.log | head -20"
