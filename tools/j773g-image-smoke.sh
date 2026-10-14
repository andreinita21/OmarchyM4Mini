#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Smoke-boot the J773g Omarchy image in QEMU (generic virt machine, TCG inside
# the Arch Linux ARM container): proves the root filesystem, the kernel package
# and systemd, not the Mac hardware. docs/j773g-image.md.
#
#   tools/j773g-image-smoke.sh [seconds]   boot build/j773g/disk/disk.img (composed
#                                          from build/j773g/image/ by
#                                          tools/j773g/compose-disk.sh when missing
#                                          or older than root.img), serial console
#                                          to build/j773g/smoke/console.log, stop
#                                          after <seconds> (default 420)
#
# Login is not possible (owner provisioning has not run); the check is that
# systemd reaches multi-user.target and the first-boot units start. QEMU runs
# with -snapshot, so disk.img (the one tools/j773g-disk.sh writes to USB) is
# never modified; the same kernel and initramfs as rung u0 are used.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
IMG=$REPO/build/j773g/image
DISK=$REPO/build/j773g/disk
WORK=$REPO/build/j773g/smoke
LIMIT=${1:-420}
mkdir -p "$WORK" "$DISK"
[[ -f $IMG/root.img && -f $IMG/boot.img ]] || { echo "no image in $IMG; run tools/j773g-image.sh first" >&2; exit 1; }
if [[ ! -s $DISK/disk.img || ! -s $DISK/u0/vmlinuz || $IMG/root.img -nt $DISK/disk.img ]]; then
  echo "== composing build/j773g/disk/disk.img from the image"
  docker run --rm --platform linux/arm64 --privileged --user root \
    -v "$REPO/tools/j773g:/tools:ro" -v "$IMG:/img:ro" -v "$DISK:/disk" \
    omarchy-j773g-alarm bash /tools/compose-disk.sh /img /disk
fi
# shellcheck disable=SC1091
source "$DISK/disk.env"

docker run --rm --platform linux/arm64 -v "$DISK:/disk:ro" -v "$WORK:/w" --user root omarchy-j773g-alarm bash -c "
  set -euo pipefail
  pacman -Sy --noconfirm --needed qemu-system-aarch64 >/dev/null
  echo \"root UUID $ROOT_UUID; booting for $LIMIT s (console -> build/j773g/smoke/console.log)\"
  timeout --foreground $LIMIT qemu-system-aarch64 -M virt -accel tcg,thread=multi -cpu max -smp 4 -m 4096 -nographic -snapshot \
    -kernel /disk/u0/vmlinuz -initrd /disk/u0/initramfs.img \
    -append \"\$(cat /disk/u0/cmdline) console=ttyAMA0 loglevel=5 systemd.unit=multi-user.target\" \
    -drive if=none,file=/disk/disk.img,format=raw,id=disk -device virtio-blk-device,drive=disk \
    -netdev user,id=n0 -device virtio-net-device,netdev=n0 -device virtio-rng-device 2>&1 | tee /w/console.log || true
  echo; echo '== verdict'
  grep -E 'Reached target .*Multi-User|Welcome to|omarchy-mac-first-boot|omarchy-provision|Failed to start|Kernel panic|login:' /w/console.log | head -20"
