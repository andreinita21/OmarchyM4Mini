#!/bin/sh
# SPDX-License-Identifier: MIT
# Part 3 of tools/j773g-install.sh (docs/j773g-install.md): run in the J773g
# RAM shell booted with `tools/j773g-boot.sh g6-display` (NVMe + Ethernet up,
# busybox). Streams root.img from the host onto the partition that `prepare`
# recorded as Gravity's root, verifies it, refreshes the Boot partition from
# boot.tar (its /boot files) and the ESP's Limine/UKI/stage 2 from esp.tar (so an image rebuilt
# after `prepare` is installed whole), and switches m1n1/boot.bin to the
# Omarchy stage 2. Sizes and sha256 come from the host's live MANIFEST, not
# from what `prepare` recorded. Nothing else on the disk is touched.
#
#   wget -O /tmp/install-root.sh http://HOST:8000/install-root.sh
#   sh /tmp/install-root.sh http://HOST:8000
#
# Checks before writing: the ESP (volume id 4F4D-5801) carries
# omarchy/j773g-install.env; the recorded partition still holds Gravity's
# root filesystem (UUID match); it is on nvme0n1, large enough, not mounted;
# the identifier is typed back. After writing: the first ROOT_IMG_BYTES of
# the partition hash to the manifest's sha256.
set -e
set -o pipefail 2>/dev/null || true

die() { echo "install-root: $*" >&2; exit 1; }

# The RAM shell's busybox has no blkid: read filesystem UUIDs from the
# superblocks directly (btrfs, ext2/3/4, FAT), printed lowercase like blkid.
rd() { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | xxd -p | tr -d '\n'; }
fsuuid() {
  local dev=$1 h o
  if [ "$(rd "$dev" $((65536 + 64)) 8)" = "5f42485266535f4d" ]; then        # "_BHRfS_M"
    h=$(rd "$dev" $((65536 + 32)) 16)
  elif [ "$(rd "$dev" $((1024 + 56)) 2)" = "53ef" ]; then                  # ext magic 0xEF53
    h=$(rd "$dev" $((1024 + 104)) 16)
  else                                                                      # FAT volume id
    if [ "$(dd if="$dev" bs=1 skip=82 count=5 2>/dev/null)" = "FAT32" ]; then o=67; else o=39; fi
    h=$(rd "$dev" $o 4)
    [ ${#h} -eq 8 ] || return 1
    echo "$(echo "$h" | cut -c7-8)$(echo "$h" | cut -c5-6)-$(echo "$h" | cut -c3-4)$(echo "$h" | cut -c1-2)"
    return 0
  fi
  [ ${#h} -eq 32 ] || return 1
  echo "$(echo "$h" | cut -c1-8)-$(echo "$h" | cut -c9-12)-$(echo "$h" | cut -c13-16)-$(echo "$h" | cut -c17-20)-$(echo "$h" | cut -c21-32)"
}
lc() { echo "$1" | tr 'A-Z' 'a-z'; }

URL=${1:?usage: sh install-root.sh http://HOST:8000}
URL=${URL%/}
ROOT_UUID=4f4d5801-524f-4f54-8000-000000000001
BOOT_UUID=4f4d5801-424f-4f54-8000-000000000001

wget -q -O /tmp/MANIFEST "$URL/MANIFEST" || die "cannot reach $URL (network up? 'serve' running?)"
manifest() { # manifest <name> <field: 2=sha256 3=size>
  awk -v n="$1" -v f="$2" '$1 == n { print $f }' /tmp/MANIFEST
}
BOOT_TAR_SHA256=$(manifest boot.tar 2)
ESP_TAR_SHA256=$(manifest esp.tar 2)
[ -n "$(manifest root.img 2)" ] && [ -n "$BOOT_TAR_SHA256" ] && [ -n "$ESP_TAR_SHA256" ] || die "root.img, boot.tar or esp.tar missing from the host's MANIFEST"

mkdir -p /mnt/esp /mnt/root
ESP_DEV=
for d in /dev/nvme0n1p*; do
  [ "$(fsuuid "$d" 2>/dev/null)" = "4f4d-5801" ] && { ESP_DEV=$d; break; }
done
[ -n "$ESP_DEV" ] || die "no FAT partition with volume id 4F4D-5801 on NVMe; did 'prepare' run in Gravity?"
grep -q "^$ESP_DEV " /proc/mounts || mount -t vfat "$ESP_DEV" /mnt/esp
[ -r /mnt/esp/omarchy/j773g-install.env ] || die "no omarchy/j773g-install.env on $ESP_DEV"
. /mnt/esp/omarchy/j773g-install.env
ENCRYPT=${ENCRYPT:-0}   # prepare's answer; an older env (no answer) means off
# prepare recorded the image it saw then; the host's MANIFEST is authoritative
ROOT_IMG_SHA256=$(manifest root.img 2); ROOT_IMG_BYTES=$(manifest root.img 3)
[ -s /mnt/esp/m1n1/boot.bin.omarchy ] || die "no m1n1/boot.bin.omarchy on the ESP"

[ -n "$ROOT_DEV" ] && [ -b "$ROOT_DEV" ] || die "ROOT_DEV '$ROOT_DEV' is not a block device here"
case $ROOT_DEV in /dev/nvme0n1p*) ;; *) die "$ROOT_DEV is not a partition of nvme0n1; refusing" ;; esac
[ "$ROOT_DEV" != "$ESP_DEV" ] || die "ROOT_DEV is the ESP; refusing"
[ -z "$BOOT_DEV" ] || [ "$ROOT_DEV" != "$BOOT_DEV" ] || die "ROOT_DEV is the Boot partition; refusing"
# Gravity's root as prepare recorded it, or Omarchy's own root from an earlier
# run of this script (a re-install); anything else is refused.
have=$(fsuuid "$ROOT_DEV" 2>/dev/null || true)
case $have in
  "$(lc "$ROOT_FS_UUID")") echo "$ROOT_DEV: Gravity's root ($have), as recorded" ;;
  "$ROOT_UUID") echo "$ROOT_DEV: Omarchy's root from an earlier install; re-installing" ;;
  *) die "$ROOT_DEV carries neither Gravity's root $ROOT_FS_UUID nor Omarchy's $ROOT_UUID (found '$have'); refusing" ;;
esac
grep -q "^$ROOT_DEV " /proc/mounts && die "$ROOT_DEV is mounted; refusing"
size=$(( $(cat "/sys/class/block/${ROOT_DEV#/dev/}/size") * 512 ))
[ "$size" -ge "$ROOT_IMG_BYTES" ] || die "$ROOT_DEV ($size B) is smaller than root.img ($ROOT_IMG_BYTES B)"

if [ -n "$BOOT_DEV" ]; then
  [ -b "$BOOT_DEV" ] || die "BOOT_DEV '$BOOT_DEV' is not a block device here"
  case $BOOT_DEV in /dev/nvme0n1p*) ;; *) die "$BOOT_DEV is not a partition of nvme0n1; refusing" ;; esac
  [ "$(fsuuid "$BOOT_DEV")" = "$BOOT_UUID" ] \
    || die "$BOOT_DEV does not carry Omarchy's Boot filesystem $BOOT_UUID (now: $(fsuuid "$BOOT_DEV")); did prepare finish?"
  grep -q "^$BOOT_DEV " /proc/mounts && die "$BOOT_DEV is mounted; refusing"
fi

echo
echo "About to replace EVERYTHING on $ROOT_DEV (Gravity's root, $(( size / 1073741824 )) GiB)"
echo "with root.img from $URL ($(( ROOT_IMG_BYTES / 1048576 )) MiB, btrfs $ROOT_UUID),"
echo "then refill Boot ${BOOT_DEV:-(none)} from boot.tar and the ESP's Limine/UKI/stage 2 from esp.tar."
echo "ESP $ESP_DEV keeps vendorfw/, omarchy/, boot.bin.gravity and boot.bin.proxy."
printf 'Type the partition name (%s) to continue: ' "${ROOT_DEV#/dev/}"
read -r typed
[ "$typed" = "${ROOT_DEV#/dev/}" ] || die "mismatch; nothing written"

echo "writing (progress is the host's HTTP log; ~3 min on gigabit)..."
wget -O - "$URL/root.img" | dd of="$ROOT_DEV" bs=4M 2>/tmp/dd.log || { cat /tmp/dd.log; die "transfer or write failed"; }
sync
echo "verifying $(( ROOT_IMG_BYTES / 1048576 )) MiB..."
got=$(head -c "$ROOT_IMG_BYTES" "$ROOT_DEV" | sha256sum | cut -d' ' -f1)
[ "$got" = "$ROOT_IMG_SHA256" ] || die "sha256 mismatch after write: $got (expected $ROOT_IMG_SHA256). Re-run."
[ "$(fsuuid "$ROOT_DEV")" = "$ROOT_UUID" ] || die "the new root does not show UUID $ROOT_UUID (now: $(fsuuid "$ROOT_DEV"))"

if [ -z "$BOOT_DEV" ]; then
  echo "no Boot partition: disabling the /boot line in the new root's fstab"
  mount -t btrfs -o subvol=@ "$ROOT_DEV" /mnt/root
  sed -i 's#^\(UUID=[^ ]*[[:space:]]*/boot[[:space:]].*\)$#\#\1#' /mnt/root/etc/fstab
  grep /boot /mnt/root/etc/fstab || true
  umount /mnt/root
fi

if [ -n "$BOOT_DEV" ]; then
  # Boot keeps the ext4 filesystem prepare made (Gravity's /boot is 1 GiB,
  # boot.img is 2 GiB): replace its contents with the image's /boot files.
  echo "refilling Boot $BOOT_DEV from boot.tar..."
  wget -q -O /tmp/boot.tar "$URL/boot.tar" || die "cannot fetch boot.tar"
  got=$(sha256sum /tmp/boot.tar | cut -d' ' -f1)
  [ "$got" = "$BOOT_TAR_SHA256" ] || die "boot.tar sha256 mismatch: $got (expected $BOOT_TAR_SHA256)"
  mkdir -p /mnt/boot
  mount -t ext4 "$BOOT_DEV" /mnt/boot || die "cannot mount $BOOT_DEV"
  for f in /mnt/boot/* /mnt/boot/.[!.]*; do
    [ -e "$f" ] || continue
    [ "${f##*/}" = "lost+found" ] && continue
    rm -rf "$f"
  done
  tar -xf /tmp/boot.tar -C /mnt/boot || die "cannot unpack boot.tar onto $BOOT_DEV"
  if [ "$ENCRYPT" = 1 ]; then
    mkdir -p /mnt/boot/omarchy && chmod 0700 /mnt/boot/omarchy
    head -c 64 /dev/urandom >/mnt/boot/omarchy/luks-key && chmod 0600 /mnt/boot/omarchy/luks-key
    echo "Boot: throwaway LUKS key staged for the first-boot conversion"
  else
    rm -f /mnt/boot/omarchy/luks-key
  fi
  sync
  ls -l /mnt/boot
  umount /mnt/boot
  rm -f /tmp/boot.tar
fi

echo "refreshing the ESP's Limine, UKI, limine.conf and stage 2 from esp.tar..."
wget -q -O /tmp/esp.tar "$URL/esp.tar" || die "cannot fetch esp.tar"
got=$(sha256sum /tmp/esp.tar | cut -d' ' -f1)
[ "$got" = "$ESP_TAR_SHA256" ] || die "esp.tar sha256 mismatch: $got (expected $ESP_TAR_SHA256)"
rm -rf /tmp/esp && mkdir -p /tmp/esp && tar -xf /tmp/esp.tar -C /tmp/esp || die "cannot unpack esp.tar"
[ -s /tmp/esp/m1n1/boot.bin ] && [ -d /tmp/esp/EFI ] && [ -s /tmp/esp/limine.conf ] || die "esp.tar lacks m1n1/boot.bin, EFI/ or limine.conf"
rm -rf /mnt/esp/EFI
cp -r /tmp/esp/EFI /mnt/esp/EFI
cp /tmp/esp/limine.conf /mnt/esp/limine.conf
# Omarchy's first boot reads this; MISSING means encrypt (and the owner setup
# then refuses an unencrypted root), so always write the recorded choice.
mkdir -p /mnt/esp/omarchy
printf 'format=1\nencrypt=%s\n' "$ENCRYPT" >/mnt/esp/omarchy/install.conf
echo "ESP: omarchy/install.conf encrypt=$ENCRYPT"
cp /tmp/esp/m1n1/boot.bin /mnt/esp/m1n1/boot.bin.omarchy
sync
rm -rf /tmp/esp /tmp/esp.tar

cp /mnt/esp/m1n1/boot.bin.omarchy /mnt/esp/m1n1/boot.bin
sync
ls -l /mnt/esp/m1n1 /mnt/esp/EFI/Linux
umount /mnt/esp
cat <<EOF

done. The ESP's m1n1/boot.bin is now the Omarchy stage 2 (m1n1 + DTB + U-Boot);
boot.bin.proxy is kept for proxy mode, boot.bin.gravity for Gravity's stage 2.
Power-cycle the mini (hold the power button, then press it): m1n1 -> U-Boot ->
Limine -> Omarchy first boot and owner setup on HDMI.
EOF
