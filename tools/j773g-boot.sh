#!/bin/bash
# SPDX-License-Identifier: MIT
# j773g-boot.sh <rung> [tag]  — one logged RAM-only J773g boot through the
# m1n1 proxy, run from the HOST (not the mini). Thin wrapper over upstream
# tools/boot.sh using the kit built by tools/j773g-build.sh:
#   build/j773g/Image.gz, build/j773g/initramfs.cpio.gz,
#   build/j773g/dtb/t8132-j773g-<rung>.dtb, build/j773g/m1n1/proxyclient/
# Rungs: r0-boot r1-smc r2-storage r3-usb r4-pcie r5-atc23 rx-all
# Env: M1N1DEVICE (required, the mini's proxy tty), PYTHON, BOOT_ARGS.
# Default args keep panics on the HDMI screen (panic=0) because the mini has
# no console-free verdict like the Air's reboot probe; override BOOT_ARGS
# with panic=-1 to get "reboot = init exited" behaviour instead.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
KIT=${BOOT_KIT:-$REPO/build/j773g}
RUNG=${1:?usage: j773g-boot.sh <rung> [tag]}
TAG=${2:-j773g-$RUNG}
DTB=$KIT/dtb/t8132-j773g-$RUNG.dtb
[[ -f $DTB ]] || { echo "no such rung DTB: $DTB" >&2; ls "$KIT/dtb" >&2; exit 2; }
export BOOT_KIT=$KIT
export BOOT_ARGS=${BOOT_ARGS:-nosmp idle=nop panic=0 console=tty0 fbcon=nodefer loglevel=7}
exec "$REPO/tools/boot.sh" "$DTB" "$TAG" "$KIT/Image.gz"
