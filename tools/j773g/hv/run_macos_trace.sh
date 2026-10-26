#!/bin/sh
# SPDX-License-Identifier: MIT
# Boot the mini's macOS (Macintosh HD, m1n1 as its custom kernel, permissive
# security) as an m1n1 hypervisor guest and trace the back-right USB-C port
# (trace_j773g_dp.py). Run on the host with the USB proxy cable plugged in,
# after the mini has started into m1n1 (startup disk = Macintosh HD).
#
#   tools/j773g/hv/run_macos_trace.sh [emulation|nested] [run_guest.py options]
#
# Keep wdt=-1: without it macOS reprograms the hardware watchdog to 5 s
# ("Reconfig Watchdog: ICC = 120000000") and, slowed down by the HV, misses
# it. tools/j773g/hv/j773g_hv_watchdog.py (pass -m) arms a 170 s one instead
# for runs expected to crash early.
#
# On the mini only "emulation" gets past hv_init (nested: undefined
# instruction right after "Enabling NV"), and SPTM halts on the PCIe DART
# ("dart-apcie2:0: unexpected dram base") unless the PCIe nodes are hidden.
#
# Images (git-ignored): build/j773g/hv/macos-<ver>/{kernelcache,sptm,txm}.macho,
# unpacked with pyimg4 from Macintosh HD's Preboot
# (boot/<hash>/System/Library/Caches/com.apple.kernelcaches/kernelcache and
# usr/standalone/firmware/FUD/Ap,{SecurePageTableMonitor,TrustedExecutionMonitor}.img4).
set -eu

repo=$(cd "$(dirname "$0")/../../.." && pwd)
hv=$repo/build/j773g/hv
img=${J773G_MACOS_IMAGES:-$hv/macos-27.0.1}
mode=${1:-emulation}
[ $# -gt 0 ] && shift
logs=$repo/build/j773g/logs
mkdir -p "$logs"
log=$logs/hv-macos-$(date +%m%d-%H%M%S)-$mode.txt

export M1N1DEVICE=${M1N1DEVICE:-$(ls /dev/cu.usbmodem* | head -n 1)}
echo "proxy: $M1N1DEVICE, sptm mode: $mode, log: $log"

# SPTM wants the guest DRAM base in the first 512 MiB of RAM; the default
# 1 GiB emulation heap pushes it past (run_guest.py patched to read this).
export M1N1_HV_HEAP_MB=${M1N1_HV_HEAP_MB:-256}
# m1n1's SPMI access before the guest starts breaks macOS's nub-spmi0 on T8132.
export M1N1_HV_NO_PMU_RESET=${M1N1_HV_NO_PMU_RESET-1}

cd "$hv/m1n1-src"
exec "$hv/venv/bin/python3" proxyclient/tools/run_guest.py \
	--sptm-mode "$mode" --strip-node apcie "$@" -p "$img/sptm.macho" -t "$img/txm.macho" \
	-m "$repo/tools/j773g/hv/sptm_amcc_ctrr.py" \
	-m "$repo/tools/j773g/hv/j773g_hv_quirks.py" \
	-m "$repo/tools/j773g/hv/trace_j773g_dp.py" \
	-l "$log" \
	"$img/kernelcache.macho" -- \
	"debug=0x14e serial=3 -enable-kprintf-spam wdt=-1 clpc=0 -v"
