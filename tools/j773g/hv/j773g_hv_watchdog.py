# SPDX-License-Identifier: MIT
# m1n1 hypervisor script (run_guest.py -m, last): arm the T8132 hardware
# watchdog (WD1, 24 MHz) just before the guest starts, so a guest SError or a
# wedged HV resets the mini back into m1n1 (startup disk = Macintosh HD)
# instead of needing a power cycle. Only for runs expected to die early:
# with wdt=-1 nothing feeds it, so the mini resets 170 s after the guest
# starts (hardware limit: 32-bit alarm, at most ~178 s). Without wdt=-1 macOS
# takes the timer over at 5 s and the slowed-down guest misses it.

WDT_BASE = 0x3882B0000
WDT_RATE = 24_000_000
WDT_COUNT, WDT_ALARM, WDT_CONTROL = 0x10, 0x14, 0x1C
WDT_SECONDS = 170

node = u.adt["/arm-io/wdt"]
if node.get_reg(0)[0] != WDT_BASE or "wdt,t8132" not in node.compatible:
    raise RuntimeError("not the J773g/T8132 watchdog")

ticks = WDT_RATE * WDT_SECONDS
p.write32(WDT_BASE + WDT_ALARM, ticks)
p.write32(WDT_BASE + WDT_COUNT, 0)
p.write32(WDT_BASE + WDT_CONTROL, 4)
if p.read32(WDT_BASE + WDT_CONTROL) != 4 or p.read32(WDT_BASE + WDT_ALARM) != ticks:
    raise RuntimeError("watchdog readback mismatch")

def wdt_feed():
    p.write32(WDT_BASE + WDT_COUNT, 0)

print(f"j773g-wdt: hardware watchdog armed, {WDT_SECONDS} s")
