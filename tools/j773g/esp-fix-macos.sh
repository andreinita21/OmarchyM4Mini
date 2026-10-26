#!/bin/bash
# SPDX-License-Identifier: MIT
# esp-fix-macos.sh <http://HOST:8000> — run on the mini, in macOS, after
# tools/j773g-install.sh prepare. Replaces the m1n1 stage 2 files on the
# Linux ESP with the NO_DISPLAY builds served by the host: m1n1/boot.bin and
# boot.bin.proxy (plain m1n1, proxy mode) and m1n1/boot.bin.omarchy (the
# Omarchy stage 2). Verifies sha256 against the host's MANIFEST, keeps the
# previous files as *.dcpcrash. Nothing else on the ESP is touched.
set -euo pipefail
base=${1:?usage: sudo bash esp-fix-macos.sh http://HOST:8000}; base=${base%/}
[[ $(uname -s) == Darwin ]] || { echo "run this in macOS on the mini" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "needs sudo" >&2; exit 1; }
work=$(mktemp -d /tmp/j773g-esp-fix.XXXXXX)
cd "$work"
curl -fsSO "$base/MANIFEST"
for f in m1n1.bin boot.bin.omarchy; do
  read -r _ sum size < <(grep "^$f " MANIFEST)
  curl -fsSO "$base/$f"
  [[ $(stat -f %z "$f") == "$size" ]] || { echo "$f: size mismatch" >&2; exit 1; }
  [[ $(shasum -a 256 "$f" | cut -d' ' -f1) == "$sum" ]] || { echo "$f: sha256 mismatch" >&2; exit 1; }
  echo "$f: downloaded and verified"
done
# Find the Linux ESP: the EFI slice that carries omarchy/j773g-install.env (written by prepare).
esp=""; mp=""
for id in $(diskutil list | awk '$2 == "EFI" || $3 == "EFI" { print $NF }'); do
  # repair first: a FAT left dirty by a power cut mounts read-only or not at all
  diskutil unmount "$id" >/dev/null 2>&1 || true
  diskutil repairVolume "$id" >/dev/null 2>&1 || true
  diskutil mount "$id" >/dev/null 2>&1 || continue
  m=$(diskutil info "$id" | awk -F': +' '/Mount Point/ { print $2 }')
  if [[ -n $m && -f $m/omarchy/j773g-install.env && -d $m/m1n1 ]]; then esp=$id; mp=$m; break; fi
  diskutil unmount "$id" >/dev/null 2>&1 || true
done
[[ -n $esp ]] || { echo "no EFI slice with omarchy/j773g-install.env found (did prepare run?)" >&2; exit 1; }
echo "Linux ESP: $esp mounted at $mp"
ls -l "$mp/m1n1"
# keep the first copy we ever saw of each file (cp -n exits 1 when the backup
# exists, which under set -e silently ended the script; hence the explicit test)
for f in boot.bin boot.bin.proxy boot.bin.omarchy; do
  if [[ -f $mp/m1n1/$f && ! -f $mp/m1n1/$f.dcpcrash ]]; then cp "$mp/m1n1/$f" "$mp/m1n1/$f.dcpcrash"; fi
done
cp m1n1.bin "$mp/m1n1/boot.bin.proxy"
cp m1n1.bin "$mp/m1n1/boot.bin"
cp boot.bin.omarchy "$mp/m1n1/boot.bin.omarchy"
sync
echo "installed:"; ls -l "$mp/m1n1"
diskutil unmount "$esp"
echo "PROXY MODE SET: m1n1/boot.bin is now the plain m1n1. Shut down, connect the USB-C cable"
echo "to the host, power on (pick the Linux volume in the startup picker if asked)."
