<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# PLAN — Linux bring-up on the base M4 Mac mini (Mac16,10 / J773g / T8132)

Status: **preliminary plan, 2026-10-13** (Fable 5.1 / high). Based on the
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
| Display | internal panel on disp0/dcp | **no panel**; HDMI via dispext0/dcpext0 + dptx-phy + DP→HDMI converter (HPD aop-gpio 41, pwr-en SMC gP0f/gP1a, reset gP10); dispext1 unused | Boot layer keeps `ps_dispext0_cpu` + `ps_dptx_phy` on (Asahi's j773g.dts). DCP later |
| Input | MTP keyboard/trackpad | **no MTP, no dockchannel-mtp** | Patches 0008, 0014 and the AFE/input kernel patches are irrelevant |
| I2C | i2c1, i2c2, i2c3 (no i2c0/i2c4) | **i2c0**, i2c1, i2c2, i2c3 (no i2c4) | i2c4 stays disabled; i2c0 exists but has no children |
| Audio | 6 speakers, J713 safety profile | **1 speaker amp TI SN012776 @ i2c3 0x38** (IRQ gpio0 14), jack codec **CS42L84 @ i2c1 0x4b** (IRQ gpio0 98), dp-audio0/1/2, MCA | Same topology as the M2 mini (t8112-j473); needs its own safety data |
| Thunderbolt | apciec0/1 | apciec0/1/**3**, acio0/1/3, retimers atcrt0/1/3 on i2c2 | No Linux driver; recorded only |
| SPI | spi2, spi4 | **spi3** (0x3_ad10c000, IRQ 1057) with the hub's NOR flash | New node only if the hub turns out to need it |

Resolved open questions: Ethernet controller found (above); the
"display-crossbar" in ioreg is `display-crossbar0` with endpoints
atc0..3/lpdptx/dptx plus the per-ATC `atcN-dpxbar` muxes upstream already
models; the mini speaker hardware is one SN012776 (TAS2764 family).

## 3. Upstream patch applicability

| Upstream file | Scope | On J773g |
|---|---|---|
| patches/0001 storage+SMC, 0002 SPI, 0003 USB/ATC, 0004 SEP, 0005 SPMI/PMU, 0007 PCIe, 0009 SIO, 0010 AOP | SoC (`t8132.dtsi`) | apply |
| patches/0006 Type-C | SoC part applies; `t8132-usbpd-spmi.dtsi` is J713-labelled | apply SoC part; mini has its own PD nodes in `dts/t8132-j773g-usb.dtsi` |
| patches/0008 MTP | SoC + J713 board | SoC part harmless (disabled); board part irrelevant |
| patches/0011 delete atc2/atc3 PMGR | J713 board | **do not apply** (real on the mini) |
| patches/0012 USB DART SIDs <1,14>, 0013 NVMe split, 0015 ANS IRQ roles | SoC | apply (mini ioreg agrees) |
| patches/0014 MTP reset GPIOs, 0016 NVMe power domain | J713 board | 0014 irrelevant; 0016 re-expressed in the storage layer |
| patches/*.dtso (cpufreq, cputemp, smc-poweroff) | J713 overlays | not qualified; cpufreq/temp are chip-level candidates later |
| patches-kernel/m4-boot-hacks-7.1.9.patch | kernel | **required** (idle=nop, WFxT delay, AIC EL2 writes) |
| patches-kernel/nvme-apple-t8132-split-nvmmu.patch | kernel | required with 0013 |
| patches-kernel/j713-input/*, j713-smc-reboot-optional-nvmem | kernel | input: irrelevant; smc-reboot: evaluate with SMC layer |
| patches-kernel/brcmfmac-bcm4388-rev6-c2-v116.patch | kernel | the mini has BCM4387; check whether it is needed at all |

Base kernel: Asahi `asahi` branch at 77cb8f24c2 (upstream's 7.1.9 freeze
point) which already contains `t8132.dtsi`, `t8132-jxxx.dtsi`,
`t8132-pmgr.dtsi` and a minimal `t8132-j773g.dts` (commit fbf2e630a9).

## 4. The layered device tree (`dts/`)

One source, preprocessor-gated layers, each its own commit:

| Layer | File | Gate | Enables | Evidence |
|---|---|---|---|---|
| 0 boot | `t8132-j773g.dts` | none | CPUs, AIC, PMGR, wdt, pinctrl, serial0, iBoot framebuffer (HDMI simpledrm) | Asahi board file + ioreg |
| 1 SMC | `t8132-j773g-smc.dtsi` | `J773G_LAYER_SMC` | smc, smc_mbox (gpio provider, hwmon) | J713-proven nodes |
| 2 storage | `t8132-j773g-storage.dtsi` | `J773G_LAYER_STORAGE` | ans_mbox, sart, nvme (APCIE_SYS_ST domain) | J713-proven; mini identical in ioreg |
| 3 USB | `t8132-j773g-usb.dtsi` | `J773G_LAYER_USB` (+`_ATC23`) | dwc3_0/1, DARTs, atcphy, SPMI PD hpm0/1/3, connectors; atc2/atc3 as new nodes | atc0/1 J713-proven; atc2/3 UNVERIFIED |
| 4 PCIe | `t8132-j773g-pcie.dtsi` | `J773G_LAYER_PCIE` | pcie0, pcie0_dart, port00 Wi-Fi/BT, pcie2_dart, port02 Ethernet, aliases | port 0 J713-proven; port 2 UNVERIFIED |
| 5 TB | `t8132-j773g-thunderbolt.dtsi` | `J773G_LAYER_THUNDERBOLT` | nothing (addresses recorded) | no driver |
| 6 display | `t8132-j773g-display.dtsi` | `J773G_LAYER_DISPLAY` | nothing yet; HDMI GPIO map; optional disp0 always-on experiment | no DCP upstream |

Build (Opus session writes the script, modelled on upstream `tools/mkdtb.sh`):
copy `dts/*` into `arch/arm64/boot/dts/apple/` of the patched kernel tree,
run the C preprocessor with `-D` flags for the wanted layers, then `dtc`.

## 5. Boot ladder (one change per attempt, RAM only)

Fixed boot args from upstream night 1:
`nosmp idle=nop panic=-1 console=tty0 fbcon=nodefer loglevel=7`.
Kernel: Asahi 77cb8f24c2 + m4-boot-hacks + split-NVMMU + T8132 DT patches,
all T8132 drivers built in; busybox initramfs that prints probe results and
`/proc/partitions` then `exec sh`.

| Rung | DTB layers | Expected | Verdict without keyboard |
|---|---|---|---|
| r0 | boot | penguin + console on HDMI, shell prompt | screen |
| r1 | +SMC | smc probe lines, hwmon | screen |
| r2 | +storage | `nvme0n1` + partitions listed | screen |
| r3 | +USB | keyboard on a rear TB port types in the shell | keyboard |
| r4 | +PCIe | `eth0` (tg3) link; Wi-Fi only with firmware | screen / `ip link` |
| r5 | +USB_ATC23 | front USB-C ports enumerate | keyboard on front port |
| later | display, TB, audio | DCP, TB, mini-specific speaker safety | — |

If r0 is black: m1n1 hypervisor does not run on T8132 (upstream finding), so
there is no virtual UART; fall back to bisecting the boot layer itself
(framebuffer power domains first).

## 6. Phase 1 — remaining steps

| # | Step | Where | Who / model | Status |
|---|------|-------|-------------|--------|
| 1 | Fork, branch j773g | mini (macOS) | done | done 2026-10-13 |
| 2 | macOS recon, ioreg + device-tree plane into `private/` | mini (macOS) | done | done 2026-10-13 |
| 2b | Preliminary layered DT + this plan | anywhere | Fable 5.1 high | done 2026-10-13 |
| 2c | Validate DT offline (`dtc`, `dtbs_check`), build env proposal, kernel + initramfs + m1n1 builds, host scripts, research, home-day checklist, README | mini (macOS, no hardware steps) | Opus 5.5 medium | **next** |
| 3 | Shrink macOS partition, install m1n1 stub (reduced security) | mini, **Andrei's approval first** | Andrei + Opus | not started |
| 4 | Host: clone fork, m1n1 proxyclient (`/usr/bin/python3` + pyserial + construct) | host | Opus | not started |
| 5 | Kernel builds: native on the mini (proposal pending) or server | mini/server | Opus | not started |
| 6 | Boot mini into m1n1 proxy, dump real ADT into `private/` | host + mini | Opus | not started |
| 7 | Diff live ADT vs this plan; final PLAN.md | host | Fable 5.1 high | not started |

## 7. Open questions

- Which rear port is the m1n1 debug/proxy (DFU) port on J773g, and which
  ATC instance each physical port maps to (hpm port-number 1/2/4).
- Whether the GL3590 front-port hub boots from its own SPI NOR without OS
  help (if not, a spi3 + firmware path is needed before front USB works).
- pwren-gpios for PCIe ports (J473 uses SMC GPIOs; none visible in ioreg).
- Whether upstream's brcmfmac BCM4388 patch matters for the mini's BCM4387.
- HPM "select" IRQs 13/39/65 (inherited inference).
- SMC shutdown-restarts issue on the mini.
