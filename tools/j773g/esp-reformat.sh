#!/bin/sh
# shellcheck shell=busybox
# SPDX-License-Identifier: MIT
# esp-reformat.sh <http://HOST:8000> [ESP device] — J773g RAM shell (busybox).
# For an ESP whose FAT is beyond repair (invalid cluster chains that come back
# after fsck): save everything readable to RAM, make a fresh FAT32 with the
# volume id Omarchy hardcodes (4F4D-5801), restore the saved files, lay down
# the served image's EFI/, limine.conf and stage 2, write omarchy/install.conf
# from the recorded ENCRYPT (default off), make boot.bin the Omarchy stage 2,
# and verify every checksum after a clean remount. Saved and restored:
# vendorfw/ (Apple firmware), omarchy/ (install env), m1n1/boot.bin.gravity,
# m1n1/boot.bin.proxy, U-Boot's ubootefi.var and Gravity's leftovers.
set -e
die() { echo "esp-reformat: $*" >&2; exit 1; }
URL=${1:?usage: sh esp-reformat.sh http://HOST:8000 [/dev/nvme0n1pN]}; URL=${URL%/}
ESP_DEV=${2:-/dev/nvme0n1p4}
wget -q -O /tmp/MANIFEST "$URL/MANIFEST" || die "cannot reach $URL"
manifest() { awk -v n="$1" -v f="$2" '$1 == n { print $f }' /tmp/MANIFEST; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
rd() { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | xxd -p | tr -d '\n'; }

mkdir -p /mnt/esp
umount /mnt/esp 2>/dev/null || true
mount -t vfat -o ro "$ESP_DEV" /mnt/esp || die "cannot mount $ESP_DEV"
[ -f /mnt/esp/omarchy/j773g-install.env ] || die "$ESP_DEV has no omarchy/j773g-install.env; is it the Linux ESP?"
. /mnt/esp/omarchy/j773g-install.env
ENCRYPT=${ENCRYPT:-0}
[ -d /mnt/esp/vendorfw ] || echo "WARNING: no vendorfw/ on this ESP"

echo "--- saving the ESP's own files to RAM (busybox tar has no --exclude: copy by name)"
rm -rf /tmp/esp-save && mkdir -p /tmp/esp-save/m1n1
# shellcheck disable=SC2045  # busybox ash; FAT names here have no spaces
for e in $(ls -A /mnt/esp); do
  case $e in
    EFI|limine.conf|limine.conf.old|m1n1|FSCK*|.Spotlight-V100|.Trashes|._*) continue ;;
  esac
  cp -a "/mnt/esp/$e" /tmp/esp-save/ || die "could not read $e; not reformatting"
  echo "  saved: $e"
done
for f in boot.bin.gravity boot.bin.proxy; do
  [ -f "/mnt/esp/m1n1/$f" ] && { cp -a "/mnt/esp/m1n1/$f" /tmp/esp-save/m1n1/ || die "could not read m1n1/$f; not reformatting"; echo "  saved: m1n1/$f"; }
done
[ -d /tmp/esp-save/vendorfw ] || echo "WARNING: vendorfw/ not in the save"
[ -f /tmp/esp-save/omarchy/j773g-install.env ] || die "the install env did not get saved"
du -sh /tmp/esp-save | sed 's/^/  save size: /'

echo "--- fetching the image's EFI files"
wget -q -O /tmp/esp.tar "$URL/esp.tar" || die "cannot fetch esp.tar"
[ "$(sha /tmp/esp.tar)" = "$(manifest esp.tar 2)" ] || die "esp.tar sha256 mismatch"
rm -rf /tmp/esp && mkdir -p /tmp/esp && tar -xf /tmp/esp.tar -C /tmp/esp
[ -s /tmp/esp/m1n1/boot.bin ] && [ -s /tmp/esp/limine.conf ] && [ -d /tmp/esp/EFI/Linux ] || die "esp.tar incomplete"
[ "$(sha /tmp/esp/m1n1/boot.bin)" = "$(manifest boot.bin.omarchy 2)" ] || die "esp.tar's stage 2 differs from boot.bin.omarchy in MANIFEST"

echo "--- reformatting $ESP_DEV (FAT32, volume id 4F4D-5801)"
umount /mnt/esp
mkdosfs -n EFI "$ESP_DEV" >/dev/null || die "mkdosfs failed"
[ "$(dd if="$ESP_DEV" bs=1 skip=82 count=5 2>/dev/null)" = "FAT32" ] || die "mkdosfs did not make FAT32"
printf '\001\130\115\117' | dd of="$ESP_DEV" bs=1 seek=67 conv=notrunc 2>/dev/null          # BS_VolID, little-endian 4F4D5801
bps=$(( 0x$(rd "$ESP_DEV" 12 1)$(rd "$ESP_DEV" 11 1) ))   # bytes per sector (the J773g NVMe has 4096)
printf '\001\130\115\117' | dd of="$ESP_DEV" bs=1 seek=$((6 * bps + 67)) conv=notrunc 2>/dev/null   # backup boot sector (BkBootSec=6)
sync
[ "$(rd "$ESP_DEV" 67 4)" = "01584d4f" ] || die "volume id not set"

echo "--- restoring"
mount -t vfat "$ESP_DEV" /mnt/esp || die "cannot mount the new filesystem"
cp -a /tmp/esp-save/. /mnt/esp/
cp -r /tmp/esp/EFI /mnt/esp/EFI
cp /tmp/esp/limine.conf /mnt/esp/limine.conf
mkdir -p /mnt/esp/m1n1 /mnt/esp/omarchy
cp /tmp/esp/m1n1/boot.bin /mnt/esp/m1n1/boot.bin.omarchy
[ -s /mnt/esp/m1n1/boot.bin.proxy ] || { wget -q -O /mnt/esp/m1n1/boot.bin.proxy "$URL/m1n1.bin" || die "cannot fetch m1n1.bin"; }
printf 'format=1\nencrypt=%s\n' "$ENCRYPT" >/mnt/esp/omarchy/install.conf
cp /mnt/esp/m1n1/boot.bin.omarchy /mnt/esp/m1n1/boot.bin
sync
umount /mnt/esp

echo "--- verifying after a clean remount"
mount -t vfat -o ro "$ESP_DEV" /mnt/esp
[ "$(sha /mnt/esp/m1n1/boot.bin)" = "$(manifest boot.bin.omarchy 2)" ] || die "boot.bin does not verify"
[ "$(sha /mnt/esp/m1n1/boot.bin.omarchy)" = "$(manifest boot.bin.omarchy 2)" ] || die "boot.bin.omarchy does not verify"
[ "$(sha /mnt/esp/EFI/Linux/omarchy_linux-gravity-m4.efi)" = "$(manifest uki.sha256 2)" ] || die "the UKI does not verify"
[ "$(sha /mnt/esp/m1n1/boot.bin.proxy)" = "$(manifest m1n1.bin 2)" ] || echo "note: boot.bin.proxy is not the served m1n1.bin"
tar -cf /dev/null -C /mnt/esp vendorfw 2>/dev/null && echo "vendorfw/ reads back" || die "vendorfw/ does not read back"
ls -l /mnt/esp /mnt/esp/m1n1 /mnt/esp/EFI/Linux; cat /mnt/esp/omarchy/install.conf
dmesg | grep -c 'FAT-fs.*error' | sed 's/^/FAT errors logged this boot (old ones included): /'
umount /mnt/esp
rm -rf /tmp/esp /tmp/esp.tar /tmp/esp-save
echo
echo "ESP REFORMAT DONE. boot.bin is the Omarchy stage 2. Unplug the USB-C cable, hold the"
echo "power button until the light goes off, press it once."
