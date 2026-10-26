#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""tools/air_watchdog.py for the M4 Mac mini (J773g): one watchdog-protected
RAM boot through the m1n1 proxy, or inspect/arm only.

Same T8132 watchdog (WD1 at 0x3882b0000, wdt,t8132); only the board check
differs. The kernel's apple_wdt (CONFIG_APPLE_WATCHDOG=y, built in) adopts
the running timer at boot (WATCHDOG_HANDLE_BOOT_ENABLED=y) and pings it from
the kernel, so a test kernel that hard-hangs stops pinging and the mini
resets; with m1n1/boot.bin = the proxy it comes back to the proxy unattended.
Arguments as air_watchdog.py (--proxyclient --device --serial --seconds --arm
--kernel --dtb --initramfs --bootargs).
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import air_watchdog as aw  # noqa: E402


def validate_j773g(chip, model, compatible, base, size):
    if (chip != 0x8132 or model != "J773gAP" or "wdt,t8132" not in compatible
            or base != aw.BASE or size != 0x4000):
        raise ValueError("target is not the J773g/T8132 watchdog")


aw.validate_target = validate_j773g

if __name__ == "__main__":
    aw.main()
