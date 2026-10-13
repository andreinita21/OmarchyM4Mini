<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Draft upstream issue — not posted

Target: https://github.com/Kb2uka/Omarchy-M4-Native/issues (new issue).
Andrei decides whether and when to post it. Keep it short; the maintainer
asked contributors to identify the exact model and to separate source
inspection from hardware observation.

---

**Title:** Heads-up: J773g (base M4 Mac mini, Mac16,10) port in progress in a fork

Hi kb2uka,

I own a base M4 Mac mini (Mac16,10 / J773g / T8132, firmware 20457.1.29) and
have started a port of this project to it in a fork:
https://github.com/andreinita21/OmarchyM4Mini (branch `j773g`, based on
`develop`).

The kernel and board device tree come from GravityLinux's `gravity-m4`
branch, whose `t8132-j773g.dts` already boots Fedora on this machine. On top
of it the fork adds a RAM-only boot ladder (m1n1 chainload from a host, one
subsystem group per boot: SMC, NVMe, USB, PCIe, cpufreq, DCP, GPU) and
J773g pieces Gravity lacks. Audio stays off until a mini-specific speaker
safety review is done; I will not reuse the `audio/j713` profiles or limits.

Your #24/#48 work carries over directly. The mini's Abbey PMU has exactly the
Air's scratchpad layout (`info-leg_scrpad` 0xf800, `pm_setting` 0x2001,
`clock_offset` 0x2100), and Gravity's T8132 tree has no `smc-reboot` /
`smc-rtc` child at all. The fork's `dts/t8132-j773g-pmu.dtsi` adds them,
with your four shutdown-state cells, as a rung to test on hardware.

J773g work stays in new files (`docs/j773g-*.md`, `dts/t8132-j773g-*`).
I understand the installer is J713-only and that nothing here qualifies
another model.

Nothing observed on hardware yet; everything so far is macOS-side recon,
offline builds and source comparison. I will report back with results.

Thanks for the groundwork.
