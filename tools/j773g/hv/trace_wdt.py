# SPDX-License-Identifier: MIT
# m1n1 hypervisor debug script (run_guest.py -m): trace the guest's accesses
# to the watchdog block (all /arm-io/wdt regs) in SYNC mode.
trace_device("/arm-io/wdt", TraceMode.SYNC)
print("j773g-wdt: tracing /arm-io/wdt")
