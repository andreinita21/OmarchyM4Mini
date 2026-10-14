#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the Omarchy image for the M4 Mac mini in the Arch Linux ARM container
# (needs tools/j773g-pkg.sh image and the packages in build/j773g/pkgs/).
# Phase 3 step P3.2, docs/j773g-phase3-plan.md §4. Writes build/j773g/image/:
# root.img (btrfs), boot.img (ext4), esp/ (m1n1 stage 2, Limine, UKI),
# installer_data.json, packages.txt, logs/.
#
#   tools/j773g-image.sh [--keep-going]        build
#   tools/j773g-image.sh shell                  root shell in the privileged container
#
# J773G_CMDLINE="nosmp idle=nop" adds kernel options (the ladder's findings).
# Nothing here touches the mini's disk; the image is a file.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=omarchy-j773g-alarm
OUT=$REPO/build/j773g/image
CACHE=$REPO/build/j773g/image-cache
PKGS=$REPO/build/j773g/pkgs
mkdir -p "$OUT" "$CACHE"
TTY=(); [[ -t 0 && -t 1 ]] && TTY=(-it)

run() {
  docker run --rm ${TTY[@]+"${TTY[@]}"} --platform linux/arm64 --privileged \
    -e BUILDER_COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    -e J773G_CMDLINE="${J773G_CMDLINE:-}" \
    -v "$REPO/tools/j773g:/tools:ro" -v "$PKGS:/pkgdest:ro" -v "$CACHE:/cache" -v "$OUT:/out" \
    --user root "$IMAGE" "$@"
}

case ${1:-} in
  shell) run bash ;;
  "" | --keep-going) run bash /tools/image-build.sh --pkgs /pkgdest --cache /cache --out /out ${1:+--keep-going} ;;
  *) sed -n 2,13p "$0"; exit 64 ;;
esac
