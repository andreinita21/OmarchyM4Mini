<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# J773g poweroff, reboot and RTC (ladder group PMU, rung g7-poweroff)

GravityLinux `gravity-m4` (4fc326f6c2) gives the SMC node only `gpio` and
`hwmon` children. With no `apple,smc-reboot` child Linux has no SMC
poweroff handler, and with no `apple,smc-rtc` child the RTC is not exposed.
On the M4 Air the same gap first hung on shutdown; adding the reboot child
without NVMEM cells then made Shut Down restart the machine (upstream
issue #24). Upstream fixed it on the Air with four PMU scratchpad cells
([docs/j713-poweroff.md](j713-poweroff.md)).

`dts/t8132-j773g-pmu.dtsi` adds, for the mini:

- the main SPMI controller `nub-spmi0` at `0x3_88714000` and the Abbey PMU
  at USID `0xe` with a fixed NVMEM layout;
- `apple,smc-reboot` with `shutdown_flag` (`0xf80f` bit 3), `boot_stage`
  (`0xf801`), `boot_error_count` / `panic_count` (`0xf802` low / high
  nibble);
- `apple,smc-rtc` with `rtc_offset` (`0x2100`, 6 bytes).

Evidence: this mini's ioreg `pmu-main@E` has exactly the Air's layout
(`info-leg_scrpad` 0xf800, `info-pm_setting` 0x2001, `info-clock_offset`
0x2100/6, `info-fault_shadow` 0x867b/0x10, `info-scrpad_socd`
0x8b00/0x1800). Gravity's kernel already builds the needed drivers
(`SPMI_APPLE`, `NVMEM_APPLE_SPMI`, `POWER_RESET_MACSMC`, `RTC_DRV_MACSMC`).

Offline checks: builds with no dtc warning; the only new dt-schema finding
is that `apple,abbey-pmic` is not yet listed in the PMIC binding (the driver
binds on the `apple,spmi-nvmem` fallback).

## Hardware test (after g6-display works)

```sh
tools/j773g-boot.sh g7-poweroff
# in the shell:
dmesg | grep -i -E 'macsmc-reboot|rtc|spmi|nvmem'   # no "Missing NVMEM cell"
cat /sys/class/rtc/rtc0/date /sys/class/rtc/rtc0/time
poweroff -f
```

Pass: the mini stays off (power LED off) and powers on normally with the
button. Fail: it restarts → record the dmesg lines in NOTES.md.

If it passes, this is a candidate patch for GravityLinux (`t8132.dtsi`,
since Abbey is the T8132 PMU on every board) and for upstream Asahi.
