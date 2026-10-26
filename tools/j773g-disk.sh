#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Rung u0 (docs/j773g-phase3-plan.md §5, P3.4): put the J773g Omarchy image on
# a USB SSD and prepare the RAM-boot kit. Nothing here can address the mini's
# internal disk: `write` refuses anything that is not a whole external USB
# disk and asks for the identifier to be typed back.
#
#   tools/j773g-disk.sh compose            build/j773g/image/{root,boot}.img + esp/
#                                          -> build/j773g/disk/disk.img (sparse GPT:
#                                          EFI 500 MB id 4F4D-5801, Boot 2 GiB, Root),
#                                          disk.env, u0/{Image.gz,initramfs.img,cmdline}
#   tools/j773g-disk.sh write <disk>       dd disk.img onto an external USB disk
#                                          (macOS: disk4 or /dev/disk4; Linux: /dev/sdX);
#                                          every byte of that disk is replaced
#   tools/j773g-disk.sh info [<disk>]      show disk.env and, on macOS, which disks
#                                          `write` would accept
#
# Then boot from the host: tools/j773g-boot.sh u0 (kernel + the image's own
# initramfs from RAM through the m1n1 proxy, root=UUID=<Omarchy root> on the
# USB disk; U0_RUNG picks the ladder DTB, default g6-display).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
IMG=$REPO/build/j773g/image
OUT=$REPO/build/j773g/disk
IMAGE=omarchy-j773g-alarm
HOST_OS=$(uname -s)

die() { echo "j773g-disk: $*" >&2; exit 1; }

compose() {
  [[ -s $IMG/root.img && -s $IMG/boot.img && -d $IMG/esp ]] || die "no image in $IMG; run tools/j773g-image.sh first"
  mkdir -p "$OUT"
  docker run --rm --platform linux/arm64 --privileged --user root \
    -v "$REPO/tools/j773g:/tools:ro" -v "$IMG:/img:ro" -v "$OUT:/out" \
    "$IMAGE" bash /tools/compose-disk.sh /img /out
  echo "j773g-disk: $(du -h "$OUT/disk.img" | cut -f1) used by the sparse disk.img ($(( $(stat -f %z "$OUT/disk.img" 2>/dev/null || stat -c %s "$OUT/disk.img") / 1048576 )) MiB apparent)"
  cat "$OUT/disk.env"
}

# macOS: accept only a whole, external, USB disk that is not the boot disk.
mac_check() {
  local dev=$1 info whole_of_root
  dev=${dev#/dev/}; dev=${dev#r}
  [[ $dev =~ ^disk[0-9]+$ ]] || die "give a whole disk identifier such as disk4 (not a slice like disk4s1)"
  info=$(diskutil info "$dev" 2>/dev/null) || die "diskutil knows no $dev"
  whole_of_root=$(diskutil info / | awk -F': *' '/Part of Whole/ { print $2 }')
  [[ $dev != "$whole_of_root" ]] || die "$dev holds macOS (the mini's internal disk). Refusing."
  grep -qE '^ *Whole: +Yes' <<<"$info" || die "$dev is not a whole disk"
  # macOS 27 dropped the "Internal:" line; "Device Location" is the check there.
  grep -qE '^ *Internal: +Yes' <<<"$info" && die "$dev is an internal disk. Refusing."
  grep -qE '^ *Protocol: +USB' <<<"$info" || die "$dev is not on USB (protocol: $(awk -F': *' '/Protocol/ { print $2 }' <<<"$info")). Refusing."
  grep -qE '^ *Device Location: +External' <<<"$info" || die "$dev is not an external device. Refusing."
  [[ " $(mac_repo_disks | tr '\n' ' ') " != *" $dev "* ]] || die "$dev holds this repository and the disk image (an external SSD used for development). Refusing."
  diskutil list "$dev"
  echo "/dev/r$dev"
}

# The whole disk(s) behind the volume that holds this checkout: the volume's
# own whole device and, for APFS, the physical store under the container.
mac_repo_disks() {
  local whole
  whole=$(diskutil info "$(df -P "$REPO" | awk 'NR == 2 { print $1 }')" 2>/dev/null | awk -F': *' '/Part of Whole/ { print $2 }')
  [[ -n $whole ]] || return 0
  echo "$whole"
  diskutil info "$whole" 2>/dev/null | awk -F': *' '/APFS Physical Store/ { print $2 }' | sed -E 's/s[0-9]+$//'
}

# Linux: whole disk on the usb transport, nothing mounted from it, not root's disk.
linux_check() {
  local dev=$1 tran type root_disk repo_disk
  [[ -b $dev ]] || die "$dev is not a block device"
  type=$(lsblk -dno TYPE "$dev"); tran=$(lsblk -dno TRAN "$dev")
  [[ $type == disk ]] || die "$dev is a $type, not a whole disk"
  [[ $tran == usb ]] || die "$dev transport is '${tran:-?}', not usb. Refusing."
  root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)
  [[ -n $root_disk && /dev/$root_disk == "$dev" ]] && die "$dev holds the running system. Refusing."
  repo_disk=$(lsblk -no PKNAME "$(findmnt -T "$REPO" -no SOURCE)" 2>/dev/null || true)
  [[ -n $repo_disk && /dev/$repo_disk == "$dev" ]] && die "$dev holds this repository and the disk image. Refusing."
  lsblk -no MOUNTPOINTS "$dev" | grep -q . && die "something from $dev is mounted; unmount it first"
  lsblk "$dev"
  echo "$dev"
}

write() {
  local target=$1 raw expected typed
  [[ -s $OUT/disk.img && -s $OUT/disk.env ]] || die "no disk.img; run: tools/j773g-disk.sh compose"
  [[ -t 0 ]] || die "write needs an interactive terminal (the identifier is typed back)"
  case $HOST_OS in
    Darwin) raw=$(mac_check "$target") ;;
    Linux) raw=$(linux_check "$target") ;;
    *) die "unsupported host $HOST_OS" ;;
  esac
  raw=$(tail -1 <<<"$raw")
  expected=${raw#/dev/}; expected=${expected#r}
  echo
  echo "About to replace EVERYTHING on $raw with build/j773g/disk/disk.img"
  echo "($(sed -n 's/^DISK_SECTORS=//p' "$OUT/disk.env") sectors, root UUID $(sed -n 's/^ROOT_UUID=//p' "$OUT/disk.env"))."
  read -r -p "Type the disk identifier ($expected) to continue: " typed
  [[ $typed == "$expected" ]] || die "identifier mismatch; nothing written"
  if [[ $HOST_OS == Darwin ]]; then
    diskutil unmountDisk force "/dev/$expected"
    sudo dd if="$OUT/disk.img" of="$raw" bs=4m status=progress
    sync
    diskutil eject "/dev/$expected" || true
  else
    sudo dd if="$OUT/disk.img" of="$raw" bs=4M status=progress conv=fsync
    sudo partprobe "$raw" 2>/dev/null || true
    lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,PARTLABEL "$raw"
  fi
  echo "j773g-disk: written. Next: tools/j773g-boot.sh u0 from the proxy host (docs/j773g-image.md, rung u0)."
}

info() {
  [[ -s $OUT/disk.env ]] && cat "$OUT/disk.env" || echo "no disk.env yet (tools/j773g-disk.sh compose)"
  if [[ $HOST_OS == Darwin ]]; then
    echo; echo "external USB whole disks diskutil sees:"
    local d
    for d in $(diskutil list | sed -n 's#^/dev/\(disk[0-9]*\) (external, physical).*#\1#p'); do
      diskutil info "$d" | grep -E '^ *(Device Identifier|Device / Media Name|Protocol|Disk Size):'
      echo
    done
  elif [[ -n ${1:-} ]]; then
    lsblk -o NAME,SIZE,TRAN,TYPE,MOUNTPOINTS "$1"
  fi
}

case ${1:-} in
  compose) compose ;;
  write) [[ -n ${2:-} ]] || die "write needs a disk (see: tools/j773g-disk.sh info)"; write "$2" ;;
  info) info "${2:-}" ;;
  *) sed -n 3,23p "$0"; exit 64 ;;
esac
