#!/bin/bash
# SPDX-License-Identifier: MIT
# j773g-build.sh <step>  — build the J773g bring-up kit in a Docker container.
# Steps: image src config dtbs check kernel initramfs m1n1 all shell
#   image      build the omarchy-j773g-build image (tools/j773g/Dockerfile)
#   src        fetch the kernel base and apply this kit's patches
#   config     arm64 defconfig + tools/j773g/kernel.fragment, report misses
#   dtbs       boot-ladder DTBs                 -> build/j773g/dtb/
#   check      same with CHECK_DTBS=y (dt-schema validation)
#   kernel     Image.gz                         -> build/j773g/Image.gz
#   kernel-gpu Rust + DRM_ASAHI_M4 kernel        -> build/j773g/Image-gpu.gz
#   initramfs  busybox initramfs                -> build/j773g/initramfs.cpio.gz
#   m1n1       m1n1.bin + proxyclient           -> build/j773g/m1n1/
#              (M1N1_FLAVOUR=gravity             -> build/j773g/m1n1-gravity/)
# Environment:
#   BASE=gravity (default) GravityLinux gravity-m4 @ GRAVITY_SHA, rungs g0..g8
#                          + "stock" (Gravity's unmodified J773g DTB)
#   BASE=asahi             legacy Asahi 77cb8f24c2 tree, rungs r0..r5,
#                          artifacts under build/j773g/asahi/
#   M4_HACKS=1             add upstream's m4-boot-hacks patch (gravity base)
#   WITH_FIRMWARE=1        initramfs includes private/firmware (Wi-Fi; see
#                          tools/j773g-wifi-fw.sh). Private output.
#   JOBS, M1N1_REF, GRAVITY_SHA
# Source trees live in the Docker volume "j773g-src" (case-sensitive, fast);
# only artifacts land in the git-ignored build/ directory.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=omarchy-j773g-build
STEP=${1:?usage: j773g-build.sh image|src|config|dtbs|check|kernel|kernel-gpu|initramfs|m1n1|all|shell}
if [[ $STEP == image || -z $(docker images -q "$IMAGE") ]]; then
  docker build -t "$IMAGE" "$REPO/tools/j773g"
  [[ $STEP == image ]] && exit 0
fi
mkdir -p "$REPO/build/j773g"
TTY=(); [[ -t 0 ]] && TTY=(-it)
exec docker run --rm ${TTY[@]+"${TTY[@]}"} \
  -e JOBS -e M1N1_REF -e BASE -e GRAVITY_SHA -e M4_HACKS -e WITH_FIRMWARE -e M1N1_FLAVOUR \
  -v j773g-src:/src \
  -v "$REPO":/repo:ro \
  -v "$REPO/build/j773g":/out \
  "$IMAGE" bash /repo/tools/j773g/inner-build.sh "$STEP"
