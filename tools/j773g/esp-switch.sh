#!/bin/sh
# SPDX-License-Identifier: MIT
# esp-switch.sh — finish part 3 by hand from the J773g RAM shell (busybox):
#   wget -O - http://HOST:8000/esp-switch.sh | sh -s http://HOST:8000
# Finds the Linux ESP (the FAT partition carrying omarchy/j773g-install.env),
# makes sure m1n1/boot.bin.omarchy, EFI/ and limine.conf match the host's
# served image (re-fetching them if not), reports Boot and the root's btrfs
# UUID, then copies boot.bin.omarchy over m1n1/boot.bin. boot.bin.proxy and
# boot.bin.gravity stay. Nothing else is written.
set -e
die() { echo "esp-switch: $*" >&2; exit 1; }
URL=${1:?usage: sh esp-switch.sh http://HOST:8000}; URL=${URL%/}
ROOT_UUID=4f4d5801-524f-4f54-8000-000000000001
wget -q -O /tmp/MANIFEST "$URL/MANIFEST" || die "cannot reach $URL"
manifest() { awk -v n="$1" -v f="$2" '$1 == n { print $f }' /tmp/MANIFEST; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

mkdir -p /mnt/esp /mnt/boot
umount /mnt/esp 2>/dev/null || true
ESP_DEV=
for d in /dev/nvme0n1p*; do
  if mount -t vfat "$d" /mnt/esp 2>/dev/null; then
    if [ -f /mnt/esp/omarchy/j773g-install.env ] && [ -d /mnt/esp/m1n1 ]; then ESP_DEV=$d; break; fi
    umount /mnt/esp
  fi
done
[ -n "$ESP_DEV" ] || die "no FAT partition with omarchy/j773g-install.env found"
echo "ESP: $ESP_DEV"
. /mnt/esp/omarchy/j773g-install.env
echo "recorded by prepare: ROOT_DEV=$ROOT_DEV BOOT_DEV=$BOOT_DEV"

echo "--- m1n1/ before:"; ls -l /mnt/esp/m1n1
want=$(manifest boot.bin.omarchy 2)
if [ ! -s /mnt/esp/m1n1/boot.bin.omarchy ] || [ "$(sha /mnt/esp/m1n1/boot.bin.omarchy)" != "$want" ]; then
  echo "boot.bin.omarchy differs from the served stage 2; fetching it"
  wget -q -O /tmp/boot.bin.omarchy "$URL/boot.bin.omarchy" || die "cannot fetch boot.bin.omarchy"
  [ "$(sha /tmp/boot.bin.omarchy)" = "$want" ] || die "boot.bin.omarchy sha256 mismatch after download"
  cp /tmp/boot.bin.omarchy /mnt/esp/m1n1/boot.bin.omarchy; sync
else
  echo "boot.bin.omarchy matches the served stage 2"
fi
want_uki=$(manifest uki.sha256 2)
have_uki=$(sha /mnt/esp/EFI/Linux/omarchy_linux-gravity-m4.efi 2>/dev/null || true)
if [ -z "$(ls /mnt/esp/EFI/Linux/*.efi 2>/dev/null)" ] || [ ! -s /mnt/esp/limine.conf ] || [ "$have_uki" != "$want_uki" ]; then
  echo "EFI/Linux or limine.conf missing or outdated; restoring from esp.tar"
  wget -q -O /tmp/esp.tar "$URL/esp.tar" || die "cannot fetch esp.tar"
  [ "$(sha /tmp/esp.tar)" = "$(manifest esp.tar 2)" ] || die "esp.tar sha256 mismatch"
  rm -rf /tmp/esp && mkdir -p /tmp/esp && tar -xf /tmp/esp.tar -C /tmp/esp
  rm -rf /mnt/esp/EFI; cp -r /tmp/esp/EFI /mnt/esp/EFI; cp /tmp/esp/limine.conf /mnt/esp/limine.conf; sync
  rm -rf /tmp/esp /tmp/esp.tar
fi
echo "--- EFI/Linux:"; ls -l /mnt/esp/EFI/Linux; grep -c . /mnt/esp/limine.conf >/dev/null && echo "limine.conf present"
if [ ! -f /mnt/esp/omarchy/install.conf ]; then
  # missing means "encrypt" to Omarchy's first boot; write prepare's choice (default off)
  printf 'format=1\nencrypt=%s\n' "${ENCRYPT:-0}" >/mnt/esp/omarchy/install.conf
fi
echo "--- omarchy/install.conf: $(tr '\n' ' ' </mnt/esp/omarchy/install.conf)"

if [ -n "$BOOT_DEV" ] && mount -t ext4 -o ro "$BOOT_DEV" /mnt/boot 2>/dev/null; then
  echo "--- Boot ($BOOT_DEV):"; ls -l /mnt/boot; umount /mnt/boot
else
  echo "--- Boot: not mounted (BOOT_DEV='$BOOT_DEV')"
fi
h=$(dd if="$ROOT_DEV" bs=1 skip=$((65536 + 32)) count=16 2>/dev/null | xxd -p)
got="$(echo "$h" | cut -c1-8)-$(echo "$h" | cut -c9-12)-$(echo "$h" | cut -c13-16)-$(echo "$h" | cut -c17-20)-$(echo "$h" | cut -c21-32)"
if [ "$got" = "$ROOT_UUID" ]; then echo "--- root $ROOT_DEV: Omarchy btrfs $got (OK)"; else die "root $ROOT_DEV does not carry Omarchy's btrfs UUID (found $got); not switching"; fi

# The installed root's own copy of the command line (used when the UKI is
# rebuilt on kernel updates): make sure it carries the J773g hardware options.
mkdir -p /mnt/root
if mount -t btrfs -o subvol=@ "$ROOT_DEV" /mnt/root 2>/dev/null; then
  # SMP line (idle=nop nohlt arm64.nowfxt efi=noruntime) instead of the old
  # single-core "nosmp idle=nop", and no Plymouth splash (it hangs the SMP
  # boot); docs/j773g-install.md.
  opts='idle=nop nohlt arm64.nowfxt efi=noruntime'
  for f in /mnt/root/etc/default/limine /mnt/root/etc/default/grub; do
    [ -f "$f" ] || continue
    sed -i 's/nosmp idle=nop *//; /^KERNEL_CMDLINE\[default\]=/s/ splash / /; /^GRUB_CMDLINE_LINUX_DEFAULT=/s/ splash / /; /^GRUB_CMDLINE_LINUX_DEFAULT=/s/"splash /"/' "$f"
  done
  f=/mnt/root/etc/default/limine
  if [ -f "$f" ] && ! grep -q "^KERNEL_CMDLINE\[default\]=.*$opts" "$f"; then
    sed -i "s|^\(KERNEL_CMDLINE\[default\]=\"\)|\1$opts |" "$f"
  fi
  grep '^KERNEL_CMDLINE' "$f" 2>/dev/null | cut -c1-120
  f=/mnt/root/etc/default/grub
  if [ -f "$f" ] && ! grep -q "^GRUB_CMDLINE_LINUX=\".*$opts" "$f"; then
    sed -i "s|^GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"$opts |" "$f"
  fi
  sync; umount /mnt/root
else
  echo "WARNING: could not mount the root subvolume to fix its command line"
fi

cp /mnt/esp/m1n1/boot.bin.omarchy /mnt/esp/m1n1/boot.bin
sync
echo "--- m1n1/ after:"; ls -l /mnt/esp/m1n1
[ "$(sha /mnt/esp/m1n1/boot.bin)" = "$want" ] || die "boot.bin does not match after copy"
umount /mnt/esp
echo
echo "SWITCH DONE. Unplug the USB-C cable from the host, hold the power button until the light"
echo "goes off, press it once: m1n1 -> U-Boot -> Limine -> Omarchy first boot on HDMI."
