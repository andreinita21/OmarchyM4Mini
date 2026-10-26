#!/bin/bash
# SPDX-License-Identifier: MIT
# j773g-boot.sh <rung> [tag]  — one logged RAM-only J773g boot through the
# m1n1 proxy, run from the HOST (not the mini). Thin wrapper over
# tools/boot.sh using the kit built by tools/j773g-build.sh:
#   build/j773g/Image.gz, build/j773g/initramfs.cpio.gz,
#   build/j773g/dtb/t8132-j773g-<rung>.dtb, build/j773g/m1n1/proxyclient/
# Rungs (Gravity base): stock g0-boot g1-smc g2-storage g3-usb g4-pcie
#   g5-cpufreq g6-display g7-poweroff g8-gpu (g8 boots Image-gpu.gz). "stock" = Gravity's unmodified J773g tree.
# Legacy Asahi rungs r0-boot..r5-atc23 use build/j773g/asahi/ automatically.
# Phase 3 rung u0: Omarchy's packaged kernel + initramfs from build/j773g/disk/u0
# (tools/j773g-disk.sh compose), root on the USB disk; env U0_RUNG (DTB rung,
# default g6-display), J773G_CMDLINE (extra options).
# Env: M1N1DEVICE (required, the mini's proxy tty), PYTHON, BOOT_ARGS.
# Default args keep panics on the HDMI screen (panic=0) because the mini has
# no console-free verdict like the Air's reboot probe; override BOOT_ARGS
# with panic=-1 to get "reboot = init exited" behaviour instead.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
KIT=${BOOT_KIT:-$REPO/build/j773g}
RUNG=${1:?usage: j773g-boot.sh <rung> [tag]}
TAG=${2:-j773g-$RUNG}
SUB=$KIT
[[ $RUNG == r[0-9]* ]] && SUB=$KIT/asahi
export BOOT_KIT=$KIT
export BOOT_ARGS=${BOOT_ARGS:-nosmp idle=nop panic=0 console=tty0 fbcon=nodefer loglevel=7}
if [[ $RUNG == u0 ]]; then
  # Phase 3 rung u0 (docs/j773g-phase3-plan.md §5): the packaged Omarchy kernel
  # and the image's own initramfs from RAM, root on the USB disk written by
  # tools/j773g-disk.sh. DTB = the highest passed ladder rung (U0_RUNG, default
  # g6-display); J773G_CMDLINE appends options.
  U0=$KIT/disk/u0
  for f in Image.gz initramfs.img cmdline; do
    [[ -s $U0/$f ]] || { echo "no u0 kit ($U0/$f); run tools/j773g-disk.sh compose" >&2; exit 2; }
  done
  DTB=$KIT/dtb/t8132-j773g-${U0_RUNG:-g6-display}.dtb
  KERNEL=$U0/Image.gz
  export BOOT_INITRD=$U0/initramfs.img
  # shellcheck disable=SC2155  # a missing cmdline fails the boot itself
  export BOOT_ARGS="$BOOT_ARGS $(<"$U0/cmdline") ${J773G_CMDLINE:-}"
else
  DTB=$SUB/dtb/t8132-j773g-$RUNG.dtb
  KERNEL=$SUB/Image.gz
  [[ $RUNG == g8-* ]] && KERNEL=$SUB/Image-gpu.gz
fi
[[ -f $DTB ]] || { echo "no such rung DTB: $DTB" >&2; ls "$KIT/dtb" >&2; exit 2; }
exec "$REPO/tools/boot.sh" "$DTB" "$TAG" "$KERNEL"
