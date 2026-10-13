#!/bin/bash
# SPDX-License-Identifier: MIT
# j773g-adt-dump.sh  — Phase 1 step 6: pull the live ADT (and the PMGR view)
# from a J773g sitting in the m1n1 proxy, into the git-ignored private/.
# Run on the HOST with the mini connected. Read-only on the target.
# Env: M1N1DEVICE (required), PYTHON, BOOT_KIT (default build/j773g).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
KIT=${BOOT_KIT:-$REPO/build/j773g}
PYTHON=${PYTHON:-python3}
: "${M1N1DEVICE:?set M1N1DEVICE to the m1n1 proxy tty of the mini}"
export M1N1DEVICE
OUT=$REPO/private/adt-live-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$OUT"
cd "$KIT/m1n1/proxyclient"
"$PYTHON" -m m1n1.adt -r "$OUT/adt-j773g.bin" > "$OUT/adt-j773g.txt"
"$PYTHON" -m m1n1.adt -a "$OUT/adt-j773g.bin" > "$OUT/adt-j773g-addr.txt"
"$PYTHON" tools/dump_pmgr.py > "$OUT/pmgr-j773g.txt" 2>&1 || echo "dump_pmgr failed (non-fatal)" >&2
"$PYTHON" tools/pmgr_adt2dt.py "$OUT/adt-j773g.bin" > "$OUT/pmgr-j773g-generated.dtsi" 2>&1 ||
  echo "pmgr_adt2dt failed (non-fatal)" >&2
ls -la "$OUT"
shasum -a 256 "$OUT/adt-j773g.bin"
echo "Never commit these files (Apple-derived). Next: Phase 1 step 7, ADT diff."
