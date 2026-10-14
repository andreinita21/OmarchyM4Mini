#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the J773g Arch packages (packaging/j773g/*) in an Arch Linux ARM
# container on the mini (Docker Desktop, arm64). Phase 3 step P3.1,
# docs/j773g-phase3-plan.md.
#
#   tools/j773g-pkg.sh image                 build the ALARM container image
#   tools/j773g-pkg.sh <pkg>...              makepkg the named packages
#   tools/j773g-pkg.sh all                   m1n1-gravity uboot-gravity linux-gravity-m4 omarchy-j773g
#   tools/j773g-pkg.sh shell                 interactive shell in the container
#
# Output: build/j773g/pkgs/*.pkg.tar.zst. Source tarballs are cached in
# build/j773g/srcdest/ (also where the ALARM rootfs for the image goes).
# JOBS=<n> limits the kernel build.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=omarchy-j773g-alarm
OUT=$REPO/build/j773g
SRCDEST=$OUT/srcdest
PKGDEST=$OUT/pkgs
ROOTFS_URL=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
mkdir -p "$SRCDEST" "$PKGDEST"

TTY=()
[[ -t 0 && -t 1 ]] && TTY=(-it)

build_image() {
  if [[ ! -f $SRCDEST/ArchLinuxARM-aarch64-latest.tar.gz ]]; then
    echo "Downloading the Arch Linux ARM rootfs..."
    curl -fL --retry 3 -o "$SRCDEST/ArchLinuxARM-aarch64-latest.tar.gz.part" "$ROOTFS_URL"
    mv "$SRCDEST/ArchLinuxARM-aarch64-latest.tar.gz.part" "$SRCDEST/ArchLinuxARM-aarch64-latest.tar.gz"
  fi
  docker build --platform linux/arm64 -t "$IMAGE" \
    -f "$REPO/tools/j773g/Dockerfile.alarm" "$SRCDEST"
}

run() {
  docker run --rm ${TTY[@]+"${TTY[@]}"} --platform linux/arm64 \
    -e JOBS="${JOBS:-}" -e SOURCE_DATE_EPOCH="$(git -C "$REPO" log -1 --format=%ct 2>/dev/null || date +%s)" \
    -v "$REPO/packaging/j773g:/repo/packaging:ro" \
    -v "$SRCDEST:/srcdest" -v "$PKGDEST:/pkgdest" \
    "$IMAGE" "$@"
}

makepkg_one() {
  local pkg=$1
  [[ -f $REPO/packaging/j773g/$pkg/PKGBUILD ]] || { echo "no packaging/j773g/$pkg/PKGBUILD" >&2; exit 1; }
  run bash -c '
    set -euo pipefail
    pkg=$1
    cp -a "/repo/packaging/$pkg" /work/build && cd /work/build
    export SRCDEST=/srcdest PKGDEST=/pkgdest
    export MAKEFLAGS="-j${JOBS:-$(nproc)}"
    export PACKAGER="OmarchyM4Mini <61935070+andreinita21@users.noreply.github.com>"
    # Local source tarballs cached in SRCDEST are picked up by makepkg; the
    # ALARM package databases are refreshed so --syncdeps can run.
    sudo pacman -Sy --noconfirm >/dev/null
    makepkg --noconfirm --syncdeps --cleanbuild --nocheck
    ls -la /pkgdest/ | grep "$pkg" || true
  ' _ "$pkg"
}

case ${1:-} in
  image) build_image ;;
  shell) run bash ;;
  all)
    for p in m1n1-gravity uboot-gravity linux-gravity-m4 omarchy-j773g; do makepkg_one "$p"; done ;;
  "" | -h | --help) sed -n 2,16p "$0" ;;
  *) for p in "$@"; do makepkg_one "$p"; done ;;
esac
