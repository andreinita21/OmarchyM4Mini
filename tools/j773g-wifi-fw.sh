#!/bin/bash
# SPDX-License-Identifier: MIT
# j773g-wifi-fw.sh  — run in macOS ON THE MINI. Copies the exact Wi-Fi
# firmware set macOS loads for THIS unit (read live from the IORegistry)
# into private/firmware/brcm/ under the generic names Linux requests on
# J773g (brcmfmac4388c0-pcie.*). Read-only on the system; output is
# Apple firmware and stays in the git-ignored private/ directory.
#
# Why not a fixed table: units differ by module vendor (V=a / V=u) and the
# NVRAM file (calibration, transmit power) differs between them.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=/usr/share/firmware/wifi
OUT=$REPO/private/firmware/brcm
sel=$(ioreg -l -w0 | LC_ALL=C grep -a -o -E '\{"Firmware"="C-4388__s-C2[^}]*\}' | head -1)
[[ -n $sel ]] || { echo "no BCM4388 C2 firmware selection in the IORegistry" >&2; exit 1; }
get() { printf '%s' "$sel" | LC_ALL=C sed -E "s/.*\"$1\"=\"([^\"]+)\".*/\\1/"; }
mkdir -p "$OUT"
copy() {
  local from=$SRC/$1 to=$OUT/$2
  [[ -f $from ]] || { echo "missing $from" >&2; exit 1; }
  cp -L "$from" "$to"
  printf '%-40s <- %s\n' "$2" "$1"
}
copy "$(get Firmware)"   brcmfmac4388c0-pcie.bin
copy "$(get NVRAM)"      brcmfmac4388c0-pcie.txt
copy "$(get Regulatory)" brcmfmac4388c0-pcie.clm_blob
copy "$(get TxCap)"      brcmfmac4388c0-pcie.txcap_blob
copy "$(get Signature)"  brcmfmac4388c0-pcie.sig
{
  echo "source: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(date -u +%FT%TZ)"
  echo "selection: $sel"
  ioreg -l -w0 | LC_ALL=C grep -a -o -E '"ModuleInfo" = "[^"]*"' | head -1
} > "$OUT/SOURCE.txt"
(cd "$OUT" && shasum -a 256 brcmfmac4388c0-pcie.* > SHA256SUMS)
echo "wrote $OUT (never commit it). Rebuild the initramfs to include it:"
echo "  WITH_FIRMWARE=1 tools/j773g-build.sh initramfs"
