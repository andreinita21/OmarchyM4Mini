#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Phase 3 §5a without a USB drive (docs/j773g-install.md): put the J773g
# Omarchy image onto the partitions the Gravity Linux installer created, in
# place. Gravity is replaced; macOS and the stub are not touched. Three parts:
#
#   tools/j773g-install.sh serve              host with build/j773g (the MacBook)
#       stages build/j773g/install/ (root.img, boot.img, esp.tar, m1n1.bin, the
#       scripts, MANIFEST) and serves it over HTTP on port 8000
#   sudo bash j773g-install.sh prepare http://HOST:8000      on the mini, in Gravity
#       ESP: backup, volume id 4F4D-5801, our Limine/UKI/limine.conf on top,
#       m1n1/boot.bin = proxy m1n1 (boot.bin.proxy), m1n1/boot.bin.omarchy =
#       the Omarchy stage 2, Gravity's old stage 2 kept as boot.bin.gravity;
#       Boot: reformatted with Omarchy's UUID and filled from boot.img;
#       omarchy/j773g-install.env on the ESP tells part 3 which partition is
#       Gravity's root. Gravity cannot boot any more afterwards.
#   tools/j773g/install-root.sh               on the mini, RAM shell (rung g6-display)
#       streams root.img from the host onto Gravity's Root partition, verifies
#       it, then switches boot.bin to the Omarchy stage 2.
#
# Undo: boot.bin.gravity (Gravity's stage 2) and esp-backup.tgz (whole ESP) are
# kept; Gravity's root is gone once part 3 has run (reinstall from their
# installer). Proxy mode again: copy m1n1/boot.bin.proxy over m1n1/boot.bin.
set -euo pipefail

# Omarchy's fixed disk identities (omarchy-mac-boot hardcodes them; the image
# builder baked them into root.img / boot.img).
ESP_VOLID=4F4D5801
BOOT_UUID=4f4d5801-424f-4f54-8000-000000000001
ROOT_UUID=4f4d5801-524f-4f54-8000-000000000001
PORT=8000

die() { echo "j773g-install: $*" >&2; exit 1; }

# ---------------------------------------------------------------- serve ----
serve() {
  local repo kit stage f ips
  repo=$(cd "$(dirname "$0")/.." && pwd)
  kit=$repo/build/j773g
  stage=$kit/install
  for f in image/root.img image/boot.img image/esp/limine.conf image/esp/m1n1/boot.bin m1n1-gravity/m1n1.bin; do
    [[ -s $kit/$f ]] || die "missing $kit/$f (tools/j773g-image.sh / tools/j773g-build.sh first)"
  done
  mkdir -p "$stage"
  ln -sfn "$kit/image/root.img" "$stage/root.img"
  ln -sfn "$kit/image/boot.img" "$stage/boot.img"
  # boot.tar = the /boot files of boot.img, for a Boot partition smaller than
  # the image (Gravity's is 1 GiB): install-root.sh refills it from this.
  [[ -s $kit/image/boot.tar ]] && ln -sfn "$kit/image/boot.tar" "$stage/boot.tar"
  ln -sfn "$kit/m1n1-gravity/m1n1.bin" "$stage/m1n1.bin"
  cp "$repo/tools/j773g-install.sh" "$repo/tools/j773g/install-root.sh" "$repo/tools/j773g/esp-fix-macos.sh" "$stage/"
  # The Omarchy stage 2 on its own, for repairing an ESP by hand (macOS or the
  # RAM shell) without unpacking esp.tar again.
  cp "$kit/image/esp/m1n1/boot.bin" "$stage/boot.bin.omarchy"
  # Everything the image's ESP carries (Limine, UKI, limine.conf, stage 2).
  (cd "$kit/image/esp" && tar cf "$stage/esp.tar" --exclude .DS_Store .)
  echo "j773g-install: hashing (root.img is $(du -h "$kit/image/root.img" | cut -f1); this takes a minute)"
  : >"$stage/MANIFEST"
  for f in root.img boot.img boot.tar esp.tar m1n1.bin boot.bin.omarchy install-root.sh; do
    [[ -e $stage/$f ]] || continue
    printf '%s %s %s\n' "$f" "$(shasum -a 256 "$stage/$f" | cut -d' ' -f1)" "$(stat -L -f %z "$stage/$f" 2>/dev/null || stat -L -c %s "$stage/$f")" >>"$stage/MANIFEST"
  done
  # the UKI's own hash, so a repair on the mini can tell an outdated EFI/Linux
  printf 'uki.sha256 %s %s\n' "$(shasum -a 256 "$kit/image/esp/EFI/Linux/"*.efi | head -1 | cut -d' ' -f1)" "$(stat -L -f %z "$kit/image/esp/EFI/Linux/"*.efi 2>/dev/null | head -1)" >>"$stage/MANIFEST"
  cat "$stage/MANIFEST"
  ips=$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" { print $2 }' | tr '\n' ' ')
  echo
  echo "Serving $stage on port $PORT. This host's addresses: ${ips:-?}"
  echo "(macOS may ask to allow incoming connections for python3; allow it.)"
  echo
  echo "On the mini, in Gravity (Ethernet plugged in):"
  echo "  curl -fO http://HOST:$PORT/j773g-install.sh && sudo bash j773g-install.sh prepare http://HOST:$PORT"
  echo
  echo "Later, in the RAM shell (tools/j773g-boot.sh g6-display), bring eth0 up:"
  # shellcheck disable=SC2016
  echo '  printf '"'"'#!/bin/sh\ncase $1 in bound|renew) ifconfig $interface $ip netmask $subnet; [ -n "$router" ] && route add default gw ${router%%%% *} $interface;; esac\n'"'"' >/tmp/d; chmod +x /tmp/d; ifconfig eth0 up; udhcpc -i eth0 -n -q -s /tmp/d'
  echo "  (or a static address: ifconfig eth0 192.168.1.50 netmask 255.255.255.0 up)"
  echo "then:"
  echo "  wget -O /tmp/install-root.sh http://HOST:$PORT/install-root.sh && sh /tmp/install-root.sh http://HOST:$PORT"
  echo
  exec python3 -m http.server "$PORT" --directory "$stage"
}

# -------------------------------------------------------------- prepare ----
fetch() { # fetch <url-base> <name> <dir>: download and check against MANIFEST
  local base=$1 name=$2 dir=$3 sum size
  read -r _ sum size < <(grep "^$name " "$dir/MANIFEST") || die "$name not in MANIFEST"
  if [[ -s $dir/$name ]] && [[ $(stat -c %s "$dir/$name") == "$size" ]] && [[ $(sha256sum "$dir/$name" | cut -d' ' -f1) == "$sum" ]]; then
    echo "  $name: already here and verified"; return
  fi
  echo "  $name: downloading ($(( size / 1048576 )) MiB)"
  curl -fL --progress-bar -o "$dir/$name" "$base/$name"
  [[ $(sha256sum "$dir/$name" | cut -d' ' -f1) == "$sum" ]] || die "$name: checksum mismatch after download"
}

prepare() {
  local base=${1:?usage: prepare http://HOST:8000}
  base=${base%/}
  [[ $(uname -s) == Linux ]] || die "prepare runs on the mini, inside Gravity Linux"
  [[ $EUID -eq 0 ]] || die "prepare needs root (sudo)"
  for c in findmnt lsblk blkid curl sha256sum tar mkfs.ext4 losetup; do
    command -v "$c" >/dev/null || die "need $c"
  done
  [[ -r /proc/device-tree/model ]] && echo "machine: $(tr -d '\0' </proc/device-tree/model)"

  # --- discover Gravity's partitions from what is mounted right now
  local root_dev esp_dev boot_dev esp_mnt disk tran chosen esp_partuuid root_partuuid root_fsuuid root_bytes boot_bytes
  root_dev=$(findmnt -no SOURCE / | sed 's/\[.*//')
  esp_mnt=$(findmnt -no TARGET /boot/efi 2>/dev/null || findmnt -no TARGET /efi 2>/dev/null || true)
  [[ -n $esp_mnt ]] || die "no ESP mounted at /boot/efi or /efi"
  esp_dev=$(findmnt -no SOURCE "$esp_mnt")
  boot_dev=$(findmnt -no SOURCE /boot 2>/dev/null || true)
  [[ $boot_dev == "$root_dev" ]] && boot_dev=
  [[ -b $root_dev && -b $esp_dev ]] || die "cannot resolve root ($root_dev) / ESP ($esp_dev) devices"
  disk=$(lsblk -no PKNAME "$root_dev")
  [[ -n $disk ]] || die "$root_dev has no parent disk"
  tran=$(lsblk -dno TRAN "/dev/$disk")
  [[ $tran == nvme ]] || die "/dev/$disk is on '$tran', not the internal NVMe; refusing"
  [[ $(lsblk -no PKNAME "$esp_dev") == "$disk" ]] || die "ESP $esp_dev is not on /dev/$disk"
  [[ -z $boot_dev || $(lsblk -no PKNAME "$boot_dev") == "$disk" ]] || die "Boot $boot_dev is not on /dev/$disk"
  [[ $(lsblk -no FSTYPE "$esp_dev") == vfat ]] || die "$esp_dev is not FAT"
  esp_partuuid=$(lsblk -no PARTUUID "$esp_dev")
  root_partuuid=$(lsblk -no PARTUUID "$root_dev")
  root_fsuuid=$(blkid -s UUID -o value "$root_dev")
  root_bytes=$(lsblk -bdno SIZE "$root_dev")
  boot_bytes=0; [[ -n $boot_dev ]] && boot_bytes=$(lsblk -bdno SIZE "$boot_dev")
  chosen=/proc/device-tree/chosen/gravity,efi-system-partition
  if [[ -r $chosen ]]; then
    [[ $(tr -d '\0' <"$chosen" | tr A-Z a-z) == "$(tr A-Z a-z <<<"$esp_partuuid")" ]] \
      || die "the firmware says the ESP is $(tr -d '\0' <"$chosen"), but $esp_dev is $esp_partuuid; refusing"
    echo "ESP confirmed by the stage 1 boot property."
  else
    echo "note: no $chosen; ESP taken from the mount table only."
  fi

  local work=/var/tmp/j773g-install
  mkdir -p "$work"
  echo "fetching the manifest from $base"
  curl -fsSL -o "$work/MANIFEST" "$base/MANIFEST" || die "cannot reach $base (is 'serve' running, same LAN, firewall allowed?)"
  local root_img_sum root_img_bytes
  read -r _ root_img_sum root_img_bytes < <(grep '^root.img ' "$work/MANIFEST")
  (( root_bytes >= root_img_bytes )) || die "Gravity's root partition ($root_bytes B) is smaller than root.img ($root_img_bytes B)"
  if [[ -n $boot_dev ]]; then (( boot_bytes >= 268435456 )) || die "Boot partition $boot_dev is smaller than 256 MiB"; fi

  local boot_desc="$boot_dev  -> ext4 $BOOT_UUID from boot.img"
  [[ -n $boot_dev ]] || boot_desc="none (part 3 disables the /boot line in Omarchy's fstab)"
  cat <<EOF

This will make Gravity Linux unbootable and prepare the mini for Omarchy:
  disk        /dev/$disk (internal NVMe)
  ESP         $esp_dev  ($esp_partuuid)  -> volume id 4F4D-5801, Omarchy's Limine/UKI/stage 2,
              m1n1/boot.bin = proxy m1n1; whole-ESP backup in $work/esp-backup.tgz
  Boot        $boot_desc
  Root        $root_dev ($root_fsuuid, $(( root_bytes / 1073741824 )) GiB)  -> NOT written now; part 3 writes root.img onto it
macOS and the stub are not touched. Every other partition on /dev/$disk is left alone.
EOF
  local typed
  read -r -p 'Type "replace gravity" to continue: ' typed
  [[ $typed == "replace gravity" ]] || die "nothing changed"

  # Disk encryption is Omarchy's first-boot decision (omarchy-mac-first-boot
  # reads omarchy/install.conf from the ESP; a MISSING file means encrypt, and
  # the owner setup then refuses an unencrypted root). Ask, default no.
  # J773G_ENCRYPT=0|1 answers without the prompt.
  local encrypt=${J773G_ENCRYPT:-}
  if [[ $encrypt != 0 && $encrypt != 1 ]]; then
    cat <<'ENC'

Disk encryption: Omarchy can encrypt the Linux root at its first boot (LUKS,
the password you choose in the owner setup unlocks it). It is off by default
for this image; the conversion runs in the first boot's initramfs and has
not been exercised on the J773g yet.
ENC
    read -r -p 'Encrypt the Linux disk at first boot? [y/N] ' typed
    case $typed in y|Y|yes|YES) encrypt=1 ;; *) encrypt=0 ;; esac
  fi
  echo "encryption: $([[ $encrypt == 1 ]] && echo ON || echo off) (omarchy/install.conf encrypt=$encrypt)"

  echo "downloading into $work"
  fetch "$base" m1n1.bin "$work"
  fetch "$base" esp.tar "$work"
  fetch "$base" install-root.sh "$work"
  [[ -n $boot_dev ]] && fetch "$base" boot.img "$work"

  # --- ESP: backup, volume id, overlay, stage-2 arrangement
  if [[ -s $work/esp-backup.tgz ]]; then
    echo "ESP: backup from an earlier run kept ($work/esp-backup.tgz)"
  else
    echo "ESP: backing up $esp_mnt"
    tar czf "$work/esp-backup.tgz" -C "$esp_mnt" .
  fi
  umount "$esp_mnt"
  if command -v fatlabel >/dev/null && fatlabel -i "$esp_dev" >/dev/null 2>&1; then
    fatlabel -i "$esp_dev" "$ESP_VOLID"
  else
    echo "ESP: fatlabel cannot set a volume id here; reformatting and restoring the backup"
    command -v mkfs.fat >/dev/null || die "need mkfs.fat"
    mkfs.fat -F 32 -i "$ESP_VOLID" -n EFI "$esp_dev" >/dev/null
    mount "$esp_dev" "$esp_mnt"
    tar xzf "$work/esp-backup.tgz" -C "$esp_mnt" --no-same-owner
    umount "$esp_mnt"
  fi
  [[ $(blkid -s UUID -o value "$esp_dev" | tr -d - | tr a-z A-Z) == "$ESP_VOLID" ]] || die "ESP volume id is not $ESP_VOLID after the change"
  mount "$esp_dev" "$esp_mnt"
  mkdir -p "$esp_mnt/m1n1"
  if [[ -s $esp_mnt/m1n1/boot.bin && ! -s $esp_mnt/m1n1/boot.bin.gravity ]] \
     && [[ $(sha256sum "$esp_mnt/m1n1/boot.bin" | cut -d' ' -f1) != "$(sha256sum "$work/m1n1.bin" | cut -d' ' -f1)" ]]; then
    cp "$esp_mnt/m1n1/boot.bin" "$esp_mnt/m1n1/boot.bin.gravity"
    echo "ESP: Gravity's stage 2 kept as m1n1/boot.bin.gravity"
  fi
  tar xf "$work/esp.tar" -C "$esp_mnt" --no-same-owner       # brings m1n1/boot.bin = Omarchy stage 2
  mv "$esp_mnt/m1n1/boot.bin" "$esp_mnt/m1n1/boot.bin.omarchy"
  cp "$work/m1n1.bin" "$esp_mnt/m1n1/boot.bin.proxy"
  cp "$work/m1n1.bin" "$esp_mnt/m1n1/boot.bin"
  [[ -d $esp_mnt/vendorfw ]] && echo "ESP: vendorfw/ (Apple firmware) kept" || echo "WARNING: no vendorfw/ on the ESP; Wi-Fi/BT firmware will be missing"
  mkdir -p "$esp_mnt/omarchy"
  cat >"$esp_mnt/omarchy/j773g-install.env" <<EOF
# written by j773g-install.sh prepare, $(date -u +%Y-%m-%dT%H:%M:%SZ); read by install-root.sh
DISK=/dev/$disk
ESP_DEV=$esp_dev
BOOT_DEV=$boot_dev
ROOT_DEV=$root_dev
ROOT_PARTUUID=$root_partuuid
ROOT_FS_UUID=$root_fsuuid
ROOT_BYTES=$root_bytes
ROOT_IMG_BYTES=$root_img_bytes
ROOT_IMG_SHA256=$root_img_sum
ENCRYPT=$encrypt
EOF
  printf 'format=1\nencrypt=%s\n' "$encrypt" >"$esp_mnt/omarchy/install.conf"
  sync

  # --- Boot: Omarchy's ext4 /boot
  if [[ -n $boot_dev ]]; then
    echo "Boot: reformatting $boot_dev as ext4 $BOOT_UUID and filling it from boot.img"
    umount "$esp_mnt" 2>/dev/null || true      # the ESP is mounted under /boot
    umount /boot 2>/dev/null || true
    if findmnt -no TARGET "$boot_dev" >/dev/null 2>&1; then
      die "$boot_dev is still mounted at $(findmnt -no TARGET "$boot_dev"); unmount it and re-run prepare"
    fi
    mkfs.ext4 -q -F -L OMARCHY_BOOT -U "$BOOT_UUID" "$boot_dev"
    local src=$work/boot-src dst=$work/boot-dst loop
    mkdir -p "$src" "$dst"
    loop=$(losetup --find --show -r "$work/boot.img")
    mount -o ro "$loop" "$src"
    mount "$boot_dev" "$dst"
    cp -a "$src/." "$dst/"
    if [[ $encrypt == 1 ]]; then
      # the throwaway key omarchy-mac-encrypt converts the root with at first
      # boot; the owner setup re-keys to the owner's password and shreds it
      install -d -m 0700 "$dst/omarchy"
      head -c 64 /dev/urandom >"$dst/omarchy/luks-key"; chmod 0600 "$dst/omarchy/luks-key"
    fi
    umount "$dst" "$src"
    losetup -d "$loop"
    sync
  fi

  cat <<EOF

prepared. The ESP now boots plain m1n1 (proxy mode) and carries Omarchy's
boot files; Boot is Omarchy's. Gravity's root is still intact but Gravity
cannot boot any more. Keep $work/esp-backup.tgz somewhere else if you want it.

Next, on this mini:   sudo poweroff     (hold the power button if it restarts)
Then from the host, USB-C in the back-middle port, mini powered on (m1n1 logo):
  export M1N1DEVICE=/dev/cu.usbmodem…     # macOS; Linux: /dev/ttyACM0
  tools/j773g-adt-dump.sh
  tools/j773g-boot.sh stock               # power-cycle between boots
  tools/j773g-boot.sh g6-display          # then, in its shell: part 3 (install-root.sh)
EOF
}

case ${1:-} in
  serve) serve ;;
  prepare) shift; prepare "$@" ;;
  *) sed -n '3,25p' "$0"; exit 64 ;;
esac
