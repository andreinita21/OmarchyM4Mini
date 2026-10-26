# SPDX-License-Identifier: MIT
# m1n1 hypervisor script (run_guest.py -m): J773g/T8132 quirks for running
# macOS 27 as a guest.
#
# ApplePMGR clears cpu-impl-reg + 0x9000 and + 0x9008 of every core while
# it starts (0x2_1105_9000 for cpu6, 0x2_1115_9000 for cpu7, ...). Natively
# the secondary cores are still off then; under the HV they run m1n1, and the
# write kills the mini (guest SError, or a dead proxy when the HV performs
# it). Drop the guest's writes to that pair on every core; reads go to the
# hardware.
#
# The same ApplePMGR routine then writes cpm-impl-reg + 0x8000 = 0,
# + 0x8008 = 0 and + 0x40f8 = 1 for each cluster. Cluster 0 takes them; on
# cluster 1, where the HV runs (cpu6 is the boot CPU), the first one is fatal.
# Drop those for the boot CPU's cluster, and its zeroing of the cluster's
# DVFS table at cpm-impl-reg - 0x20000 + 0x400..0x5ff (0x2_11e2_0400 on
# cluster 1): with that let through, the mini resets ("wdog") ~1.5 s later.

#
# AppleARMWatchdogTimer arms the SMC "simple reconfig" watchdog from the ADT
# (simple-reconfig-wdog-support, icc-time 5 s, "Reconfig Watchdog: ICC =
# 120000000"); wdt=-1 does not cover it and the guest, slowed by the HV,
# misses the check-in, so the SMC resets the mini ~5 s into the boot.
# Without the property the driver falls back to 15 s. Give it 89 s (ICC is
# icc-time x 24 MHz; 89 s keeps it below 2^31).
from m1n1.utils import irange

hv.adt["/arm-io/wdt"].simple_reconfig_wdog_icc_time = 89

QUIRK_WRITE_DROP = tuple(cpu.cpu_impl_reg[0] + off
                         for cpu in hv.adt["/cpus"]
                         for off in (0x9000, 0x9008))
_boot = next(cpu for cpu in hv.adt["/cpus"] if cpu.state == "running")
QUIRK_WRITE_DROP += tuple(_boot.cpm_impl_reg[0] + off for off in (0x8000, 0x8008, 0x40f8))
QUIRK_WRITE_DROP += tuple(_boot.cpm_impl_reg[0] - 0x20000 + off for off in range(0x400, 0x600, 8))

def _drop_write(base, off, data, width):
    hv.log(f"j773g-quirk: dropped W {base + off:#x} = {data!r}")

def _read(base, off, width):
    return p.read64(base + off) if width == 64 else p.read32(base + off)

for addr in QUIRK_WRITE_DROP:
    hv.map_hook(addr, 8, write=_drop_write, read=_read)
    hv.add_tracer(irange(addr, 8), "J773G QUIRK", TraceMode.RESERVED)

print(f"j773g-quirk: dropping guest writes to {', '.join(hex(a) for a in QUIRK_WRITE_DROP)}")
