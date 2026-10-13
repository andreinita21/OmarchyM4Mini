#!/bin/bash
# SPDX-License-Identifier: MIT
# j773g-build.sh <step>  — build the J773g bring-up kit in a Docker container.
# Steps: image src config dtbs check kernel initramfs m1n1 all shell
#   image      build the omarchy-j773g-build image (tools/j773g/Dockerfile)
#   src        fetch Asahi 77cb8f24c2, apply T8132 SoC + kernel patches
#   config     arm64 defconfig + tools/j773g/kernel.fragment, report misses
#   dtbs       boot-ladder DTBs r0..r5 + rx-all  -> build/j773g/dtb/
#   check      same with CHECK_DTBS=y (dt-schema validation)
#   kernel     Image.gz                          -> build/j773g/Image.gz
#   initramfs  busybox initramfs                 -> build/j773g/initramfs.cpio.gz
#   m1n1       m1n1.bin + proxyclient            -> build/j773g/m1n1/
#              (M1N1_FLAVOUR=gravity              -> build/j773g/m1n1-gravity/)
#   gravity    control kernel + DTB from GravityLinux gravity-m4 -> build/j773g/gravity/
# Source trees live in the Docker volume "j773g-src" (case-sensitive, fast);
# only artifacts land in the git-ignored build/ directory.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=omarchy-j773g-build
STEP=${1:?usage: j773g-build.sh image|src|config|dtbs|check|kernel|initramfs|m1n1|gravity|all|shell}
if [[ $STEP == image || -z $(docker images -q "$IMAGE") ]]; then
  docker build -t "$IMAGE" "$REPO/tools/j773g"
  [[ $STEP == image ]] && exit 0
fi
mkdir -p "$REPO/build/j773g"
TTY=(); [[ -t 0 ]] && TTY=(-it)
exec docker run --rm ${TTY[@]+"${TTY[@]}"} \
  -e JOBS -e M1N1_REF -e GRAVITY_REF -e M1N1_FLAVOUR \
  -v j773g-src:/src \
  -v "$REPO":/repo:ro \
  -v "$REPO/build/j773g":/out \
  "$IMAGE" bash /repo/tools/j773g/inner-build.sh "$STEP"
