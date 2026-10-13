<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# PLAN — Linux bring-up on the base M4 Mac mini (Mac16,10 / J773g / T8132)

Status: **preliminary plan, 2026-10-13** (Fable 5.1 / high); facts updated
2026-10-14 (Opus 5.5) from web research and GravityLinux's hardware-tested
J773g tree — see `docs/j773g-research.md`. Based on the
macOS IORegistry dump of this mini (`private/iodevicetree-j773g.txt`, the
ADT as macOS exposes it), upstream's J713 patches and audit, and Asahi's own
`t8132-j773g.dts`. Every mini-specific value is **UNVERIFIED** until the live
ADT is dumped through m1n1 (Phase 1 step 6) and the node has booted. The
final plan replaces this file after that diff (Phase 1 step 7).

Rules live in `START_HERE.md`; the running log in `NOTES.md`.

## 1. Win condition and constraints

Linux kernel booted on J773g via m1n1 chainload (RAM only, driven from a host
over USB-C), busybox shell on HDMI with a USB keyboard. Stretch: NVMe root,
Ethernet, GPU. Out of scope this weekend: audio, full display controller,
installer, suspend/shutdown, Thunderbolt.

- macOS stays intact; no disk, partition or boot-policy writes without
  Andrei's explicit approval for that action. Dev boots are RAM-only.
- Raw dumps, firmware and logs stay in git-ignored `private/`.
- Never reuse `audio/j713` speaker data on the mini.
- J773g work in new files (`dts/`, `docs/j773g-*.md`, later `audio/j773g/`).

## 2. What the mini's tree says (ioreg, 2026-10-13)

Identity: Mac16,10, target-type J773g, chip-id 0x8132, board-id 0x2a,
soc-generation H16, chip-revision 0x11, 10 CPUs (6× sawtooth E, 4× everest
P), 16 GB, iBoot 20457.1.29, Wi-Fi module instance "sakhalin".

| Area | J713 (M4 Air, upstream) | J773g (this mini) | Consequence |
|---|---|---|---|
| PMGR table | 392 records; 14 atc2/atc3 providers virtual-only | 393 records; **all 129 providers in `t8132-pmgr.dtsi` have real records**, incl. every atc2/atc3 domain; same 3 always-on policy differences (aic, disp_sys, disp_fe) | **Do not apply patch 0011.** `t8132-pmgr.dtsi` usable unchanged |
| USB/Type-C | atc0, atc1 | atc0, atc1, **atc2, atc3**; hpm0 (USID 0xC), hpm1 (0xA), hpm3 (0x8); atc2 has no PD controller and feeds a GL3590 hub (front USB-C) with firmware on SPI3 NOR | USB layer: atc0/1 from upstream; atc2/3 new nodes (`-DJ773G_LAYER_USB_ATC23`) |
| Storage | ANS2 split window, IRQs 1004/1003/1006/1005/1018 | identical (nvme-secure-bar, sart v3, same PMGR offsets) | Patches 0001, 0013, 0015 apply; 0016 re-expressed at board level |
| SMC | 0x3_8c600000, IRQs 562/561/564/563 | identical; charger-util 0/1/3 (one per TB port) | Patch 0001 applies; shutdown issue (#24) expected too |
| PCIe | port 0 (Wi-Fi/BT) only; one DART | port 0 Wi-Fi/BT (**same pins 160/163, SIDs 1/2**) + **port 2 Ethernet** BCM57762 (pci14e4,1682, tg3), own DART 0x4_92000000 IRQ 1250 SID 1, pins 162/165 | Patch 0007 applies; add pcie2_dart, port02, aliases |
| Display | internal panel on disp0/dcp | **no panel**; HDMI via dispext0/dcpext0 + dptx-phy + DP→HDMI converter (HPD aop-gpio 41, pwr-en SMC gP0f/gP1a, reset gP10); dispext1 unused | Boot layer keeps `ps_dispext0_fe` + `ps_dptx_phy` on (Gravity's fix; Asahi's `_cpu` domain defers simpledrm). DCP later |
| Input | MTP keyboard/trackpad | **no MTP, no dockchannel-mtp** | Patches 0008, 0014 and the AFE/input kernel patches are irrelevant |
| I2C | i2c1, i2c2, i2c3 (no i2c0/i2c4) | **i2c0**, i2c1, i2c2, i2c3 (no i2c4) | i2c4 stays disabled; i2c0 exists but has no children |
| Audio | 6 speakers, J713 safety profile | **1 speaker amp TI SN012776 @ i2c3 0x38** (IRQ gpio0 14), jack codec **CS42L84 @ i2c1 0x4b** (IRQ gpio0 98), dp-audio0/1/2, MCA | Same topology as the M2 mini (t8112-j473); needs its own safety data |
| Thunderbolt | apciec0/1 | apciec0/1/**3**, acio0/1/3, retimers atcrt0/1/3 on i2c2 | No Linux driver; recorded only |
| SPI | spi2, spi4 | **spi3** (0x3_ad10c000, IRQ 1057) with the hub's NOR flash | New node only if the hub turns out to need it |

Resolved open questions: Ethernet controller found (above); the
"display-crossbar" in ioreg is `display-crossbar0` with endpoints
atc0..3/lpdptx/dptx plus the per-ATC `atcN-dpxbar` muxes upstream already
models; the mini speaker hardware is one SN012776 (TAS2764 family).

## 3. Kernel base: GravityLinux `gravity-m4` (decided 2026-10-14)

Andrei chose Gravity on 2026-10-14. Base = `GravityLinux/linux` branch
`gravity-m4`, pinned at **4fc326f6c2** (7.1.13). Its `t8132-j773g.dts` has
booted Fedora on M4 minis (native HDMI via DCP, NVMe, USB incl. front hub,
Ethernet, cpufreq, speaker). Consequences:

| Upstream Omarchy file | On the Gravity base |
|---|---|
| patches/0001–0016 (T8132 DT slices, J713 fixes) | not used; Gravity's `t8132.dtsi` already carries these subsystems |
| patches-kernel/m4-boot-hacks-7.1.9.patch | applies cleanly but **not needed** (Gravity boots without it); available as `M4_HACKS=1` fallback |
| patches-kernel/nvme-apple-t8132-split-nvmmu.patch | conflicts; Gravity has its own T8132 NVMe driver |
| patches-kernel/brcmfmac-bcm4388-rev6-c2-v116.patch | conflicts; check whether Gravity's brcmfmac already handles 4388 C2 |
| patches-kernel/j713-smc-reboot-optional-nvmem.patch | applies; relevant to the shutdown question (section 7) |
| patches-kernel/j713-input/* | irrelevant (no MTP on the mini) |
| patches/j713-*.dtso | J713 only |

The Asahi-based layered tree from 2026-10-13 is kept in `dts/asahi/` and
still builds with `BASE=asahi` (rungs r0–r5, artifacts in
`build/j773g/asahi/`), as a fallback and for comparison.

## 4. The device tree ladder (`dts/t8132-j773g-ladder.dtsi`)

Each rung = Gravity's unmodified `t8132-j773g.dts` + the ladder include,
which forces `status = "disabled"` on every group the rung does not name.
**Audio (speaker-audio, i2c3 amp, MCA, ADMAC, audio DART, DP audio) is
disabled in every rung**, and the speaker/amp/MCA drivers are compiled out,
until a J773g speaker safety profile has been reviewed.

| Group | Nodes |
|---|---|
| SMC | smc_mbox, smc, pcie0-port0 pwren regulator |
| STORAGE | ans_mbox, sart, nvme |
| USB | nub_spmi_a0/a1, dwc3_0..3 + DARTs, atcphy0..3 |
| PCIE | pcie0, pcie0_dart, pcie2_dart (needs SMC) |
| CPUFREQ | cpufreq_e, cpufreq_p |
| DISPLAY | display-subsystem, dcp/dcpext DARTs + mailboxes, dptxphy, SIO |
| GPU | agx_mbox (m1n1 enables the GPU node itself; no DRM_ASAHI in this kernel yet) |

Validated offline: every rung builds; each rung adds exactly its group's
nodes (checked by walking the DTBs); dt-schema finds nothing beyond the 39
findings of Gravity's stock DTB.

## 5. Boot ladder (one change per attempt, RAM only)

Boot args: `nosmp idle=nop panic=0 console=tty0 fbcon=nodefer loglevel=7`
(`tools/j773g-boot.sh` default; conservative, Gravity itself needs neither
`nosmp` nor `idle=nop` as far as its image recipes show). Kernel: gravity-m4
+ `tools/j773g/kernel.fragment` (all needed drivers built in, simpledrm
console, DCP driver built in, pstore/ramoops, no Rust/GPU, no speaker
drivers). Busybox initramfs prints probe lines, the previous boot's pstore
console if any, partitions, links, then a shell.

| Rung | Groups | Expected | Verdict without keyboard |
|---|---|---|---|
| stock | Gravity's own DTB (control) | console on HDMI, shell | screen |
| g0-boot | none | penguin + console on HDMI, shell prompt | screen |
| g1-smc | +SMC | macsmc probe lines, hwmon | screen |
| g2-storage | +STORAGE | `nvme0n1` + partitions listed (nothing mounts it) | screen |
| g3-usb | +USB | keyboard types in the shell (any port) | keyboard |
| g4-pcie | +PCIE | `eth0` (tg3); Wi-Fi needs firmware | `ip link` |
| g5-cpufreq | +CPUFREQ | no hang under load; `/sys/devices/system/cpu/cpufreq` | keyboard |
| g6-display | +DISPLAY | appledrm takes over HDMI from simpledrm | screen |
| later | GPU (Rust kernel), Wi-Fi/BT firmware, audio with reviewed safety data | — | — |

If a rung is black: boot `stock`; then warm-reboot into `g0-boot` and read
the previous console from pstore (printed by the initramfs). The m1n1
hypervisor is gaining M4 support upstream; try `run_guest.py` last.

## 6. Phase 1 — remaining steps

| # | Step | Where | Who / model | Status |
|---|------|-------|-------------|--------|
| 1 | Fork, branch j773g | mini (macOS) | done | done 2026-10-13 |
| 2 | macOS recon, ioreg + device-tree plane into `private/` | mini (macOS) | done | done 2026-10-13 |
| 2b | Preliminary layered DT + this plan | anywhere | Fable 5.1 high | done 2026-10-13 |
| 2c | Validate DT offline (`dtc`, `dtbs_check`), build env, kernel + initramfs + m1n1 builds, host scripts, research, home-day checklist, README | mini (macOS, no hardware steps) | Opus 5.5 medium | done 2026-10-14 |
| 3 | Shrink macOS partition, install m1n1 stub via the Gravity Linux installer (route A, chosen 2026-10-14), then stage 2 = plain m1n1 for proxy mode | mini, **Andrei's approval first** | Andrei + Opus | not started; steps in `docs/j773g-home-day-checklist.md` |
| 4 | Host: clone fork, m1n1 proxyclient (`python3` + pyserial 3.5 + construct 2.10.70), copy the boot kit | host | Opus | not started |
| 5 | Kernel builds: Docker on the mini (`tools/j773g-build.sh`), ~6 min full build; rebased on Gravity gravity-m4 | mini | Opus | done 2026-10-14 |
| 6 | Boot mini into m1n1 proxy, dump real ADT into `private/` | host + mini | Opus | not started |
| 7 | Diff live ADT vs this plan; final PLAN.md | host | Fable 5.1 high | not started |

## 7. Open questions

Answered 2026-10-14 (details and sources in `docs/j773g-research.md`):
DFU/proxy port = back-middle = atc0 (back-left atc1, back-right atc3, front
ports via hub on atc2); the GL3590 hub boots from its own NOR once GPIO 101
(flash OE) and 198 (reset) are driven high; port 0 pwren = SMC GPIO 19
(inherited from Gravity); Wi-Fi is BCM4388 C2 so the 4388 patch matters;
HPM select IRQs 13/39/65 match Gravity's hardware-tested values.

Decided 2026-10-14: kernel base = Gravity `gravity-m4`; stub route =
Gravity installer (home-day checklist, route A).

Still open:
- SMC shutdown on the mini: Gravity's tree has no `macsmc-reboot` NVMEM
  cells either, which is what made the Air restart instead of power off
  (upstream issue #24, PR #48). Candidate J773g fix, needs a hardware test.
- Whether the m1n1 hypervisor now works on T8132 (fixes landing upstream).
- GPU: needs a Rust-enabled kernel build (DRM_ASAHI_M4) in the container.
- Wi-Fi/BT firmware for BCM4388 C2 "sakhalin" (Gravity's fwextract).
- Speaker safety profile for the SN012776 + mini enclosure (review Gravity's
  `apple,j773g-speaker` driver before any audio rung).
