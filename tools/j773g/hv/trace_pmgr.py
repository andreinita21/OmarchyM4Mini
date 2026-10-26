# SPDX-License-Identifier: MIT
# m1n1 hypervisor debug script (run_guest.py -m): trace every PMGR register
# access in SYNC mode, except the PS registers the HV already hooks (UART0,
# the proxy's ATC USB domains and their parents), to find the access that
# raises a guest SError during ApplePMGR start.
from m1n1.utils import irange
from m1n1.proxy import IODEV

pmgr = hv.adt["/arm-io/pmgr"]
dev_by_name = {dev.name: dev for dev in pmgr.devices}
dev_by_id = {hv.adt.pmgr_dev_get_id(dev): dev for dev in pmgr.devices}
idx = hv.iodev - IODEV.USB0
skip = set()

def add(dev):
    skip.add(hv.adt.pmgr_dev_get_addr(dev))
    for parent in hv.adt.pmgr_dev_get_parents(dev):
        if parent in dev_by_id:
            add(dev_by_id[parent])

for name in ("UART0", f"ATC{idx}_USB", f"ATC{idx}_USB_AON"):
    add(dev_by_name[name])

WDT_COUNT = 0x3882B0010  # j773g_hv_watchdog.py: feed it while tracing slows the boot

def _event(evt, **kw):
    p.write32(WDT_COUNT, 0)
    hv.print_tracer.event_mmio(evt, **kw)

def _trace(zone):
    hv.add_tracer(zone, "PrintTracer", TraceMode.SYNC, _event, _event,
                  start=zone.start, name="pmgr")

for i in range(len(pmgr.reg)):
    start, size = pmgr.get_reg(i)
    cur = start
    for a in sorted(x for x in skip if start <= x < start + size):
        if a > cur:
            _trace(irange(cur, a - cur))
        cur = a + 4
    if cur < start + size:
        _trace(irange(cur, start + size - cur))
print(f"j773g-pmgr: tracing {len(pmgr.reg)} PMGR ranges, skipping {len(skip)} hooked PS regs")
