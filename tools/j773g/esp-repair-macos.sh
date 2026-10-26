#!/bin/bash
# SPDX-License-Identifier: MIT
# esp-repair-macos.sh <http://HOST:8000> — run on the mini, in macOS, when the
# Linux ESP was left inconsistent (power lost during install-root.sh):
#   curl -fO http://HOST:8000/esp-repair-macos.sh && sudo bash esp-repair-macos.sh http://HOST:8000
# Repairs the FAT filesystem (fsck via diskutil), then brings the ESP to the
# served image's state: m1n1/boot.bin.omarchy, EFI/ and limine.conf from the
# host (sha256-checked against MANIFEST), keeps vendorfw/, omarchy/,
# boot.bin.proxy and boot.bin.gravity, checks the root partition carries
# Omarchy's btrfs, and finally copies boot.bin.omarchy over m1n1/boot.bin.
set -euo pipefail
base=${1:?usage: sudo bash esp-repair-macos.sh http://HOST:8000}; base=${base%/}
[[ $(uname -s) == Darwin ]] || { echo "run this in macOS on the mini" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "needs sudo" >&2; exit 1; }
ROOT_UUID=4f4d5801-524f-4f54-8000-000000000001
work=$(mktemp -d /tmp/j773g-esp-repair.XXXXXX); cd "$work"
curl -fsSO "$base/MANIFEST"
manifest() { awk -v n="$1" -v f="$2" '$1 == n { print $f }' MANIFEST; }
fetch() { curl -fsSO "$base/$1"; [[ $(shasum -a 256 "$1" | cut -d' ' -f1) == "$(manifest "$1" 2)" ]] || { echo "$1: sha256 mismatch" >&2; exit 1; }; echo "$1: downloaded and verified"; }
fetch boot.bin.omarchy; fetch esp.tar
mkdir esp && tar -xf esp.tar -C esp

# 1. repair + mount the Linux ESP (the EFI slice carrying omarchy/j773g-install.env)
esp=""; mp=""
for id in $(diskutil list | awk '$2 == "EFI" || $3 == "EFI" { print $NF }'); do
  diskutil unmount "$id" >/dev/null 2>&1 || true
  echo "--- diskutil repairVolume $id"; diskutil repairVolume "$id" || true
  diskutil mount "$id" >/dev/null 2>&1 || continue
  m=$(diskutil info "$id" | awk -F': +' '/Mount Point/ { print $2 }')
  if [[ -n $m && -f $m/omarchy/j773g-install.env && -d $m/m1n1 ]]; then esp=$id; mp=$m; break; fi
  diskutil unmount "$id" >/dev/null 2>&1 || true
done
[[ -n $esp ]] || { echo "no EFI slice with omarchy/j773g-install.env found" >&2; exit 1; }
echo "Linux ESP: $esp at $mp"
# shellcheck disable=SC1091
source "$mp/omarchy/j773g-install.env"
echo "recorded by prepare: ROOT_DEV=$ROOT_DEV BOOT_DEV=$BOOT_DEV"
echo "--- m1n1/ before:"; ls -l "$mp/m1n1"

# 2. root partition must carry Omarchy's btrfs (install-root.sh wrote and verified it)
disk=${esp%s*}; rootdev=/dev/${disk}s${ROOT_DEV##*p}
h=$(dd if="$rootdev" bs=512 skip=128 count=1 2>/dev/null | xxd -p -s 32 -l 16 | tr -d '\n')   # btrfs fsid at 65536+32
got="${h:0:8}-${h:8:4}-${h:12:4}-${h:16:4}-${h:20:12}"
[[ $got == "$ROOT_UUID" ]] || { echo "root $rootdev does not carry Omarchy's btrfs (found $got); not switching" >&2; exit 1; }
echo "root $rootdev: Omarchy btrfs $got (OK)"

# 3. bring the ESP to the image's state
rm -f "$mp/m1n1/boot.bin.omarchy"
cp boot.bin.omarchy "$mp/m1n1/boot.bin.omarchy"
rm -rf "$mp/EFI"; cp -R esp/EFI "$mp/EFI"; cp esp/limine.conf "$mp/limine.conf"
# Omarchy's first boot treats a missing omarchy/install.conf as "encrypt"; keep
# prepare's recorded choice (ENCRYPT in the env, default off).
[[ -f $mp/omarchy/install.conf ]] || printf 'format=1\nencrypt=%s\n' "${ENCRYPT:-0}" >"$mp/omarchy/install.conf"
[[ -s $mp/m1n1/boot.bin.proxy ]] || cp "$mp/m1n1/boot.bin" "$mp/m1n1/boot.bin.proxy"
sync
# 4. the switch
cp "$mp/m1n1/boot.bin.omarchy" "$mp/m1n1/boot.bin"; sync
[[ $(shasum -a 256 "$mp/m1n1/boot.bin" | cut -d' ' -f1) == "$(manifest boot.bin.omarchy 2)" ]] || { echo "boot.bin mismatch after copy" >&2; exit 1; }
echo "--- m1n1/ after:"; ls -l "$mp/m1n1"; echo "--- EFI/Linux:"; ls -l "$mp/EFI/Linux"; ls "$mp/vendorfw" >/dev/null 2>&1 && echo "vendorfw/ present" || echo "WARNING: no vendorfw/ on the ESP"
diskutil unmount "$esp"
echo; echo "SWITCH DONE. Shut down macOS, unplug the USB-C cable from the host, power on:"
echo "m1n1 -> U-Boot -> Limine -> Omarchy first boot on HDMI."
