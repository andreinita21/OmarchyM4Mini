<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# OmarchyM4Mini — Linux bring-up on the base M4 Mac mini

> [!WARNING]
> **Experimental, pre-boot research. Nothing here installs anything, and nothing
> here has booted on a Mac mini yet.** Device trees, kernel patches and notes
> for the base **M4 Mac mini — Mac16,10 / J773g / T8132**. Running any of it can
> cause data loss, boot failures or hardware damage. Keep a working recovery
> path (1TR via a long power-button press, DFU revive from a second Mac).
> Provided “AS IS”, without warranty of any kind.

This is a fork of [Kb2uka/Omarchy-M4-Native](https://github.com/Kb2uka/Omarchy-M4-Native),
the experimental Omarchy/Asahi bring-up for the 13-inch M4 MacBook Air
(Mac16,12 / J713). The two machines share the T8132 SoC, so CPU bring-up, AIC,
PMGR, NVMe, SMC basics and the GPU carry over. The board is different: no
internal panel (HDMI and Thunderbolt only), no internal keyboard or trackpad,
Gigabit Ethernet, four USB/Type-C controllers instead of two, and a different
speaker. This fork adds the J773g pieces in new files next to the J713 ones.

**There is no installer for the mini.** Upstream's J713 installer refuses
other boards on purpose; do not try to use it here.

Not an official release. Not sponsored, approved or endorsed by Omarchy /
Basecamp, Asahi Linux, Gravity Linux, Apple, or Kb2uka.

## Status

| Step | State |
| --- | --- |
| macOS-side recon (ioreg / IODeviceTree), preliminary plan | done — [PLAN.md](PLAN.md) |
| Layered J773g device tree, offline-validated (dtc + dt-schema) | done — [dts/](dts/) |
| Containerised kernel / DTB / initramfs / m1n1 build | done — [tools/j773g-build.sh](tools/j773g-build.sh) |
| m1n1 stub on the mini, live ADT dump through m1n1 | not started (needs a second machine and the owner's go-ahead) |
| First RAM-only boot to a busybox shell on HDMI | not started |

The running log is [NOTES.md](NOTES.md); the next hardware session follows
[docs/j773g-home-day-checklist.md](docs/j773g-home-day-checklist.md).

## Layout

| Path | What |
| --- | --- |
| [START_HERE.md](START_HERE.md) | Project brief and safety rules |
| [PLAN.md](PLAN.md) | J713-vs-J773g comparison, patch applicability, boot ladder |
| [NOTES.md](NOTES.md) | One entry per setup step or boot attempt |
| [dts/](dts/) | `t8132-j773g.dts` plus one include per subsystem, gated on `-DJ773G_LAYER_*` |
| [tools/j773g-build.sh](tools/j773g-build.sh), [tools/j773g/](tools/j773g/) | Docker build: Asahi `77cb8f24c2` + T8132 patches, ladder DTBs r0..r5, busybox initramfs, m1n1 |
| [tools/j773g-boot.sh](tools/j773g-boot.sh) | One logged RAM-only boot of a ladder rung through the m1n1 proxy (run on the host) |
| [tools/j773g-adt-dump.sh](tools/j773g-adt-dump.sh) | Pull the live ADT into the git-ignored `private/` |
| `docs/j773g-*.md` | Mini-specific notes |
| everything else | Upstream's J713 work, unchanged; its front page is now [docs/upstream-README.md](docs/upstream-README.md) |

## The device tree layers

One source builds any subset, so each boot attempt adds one subsystem:

| Rung | Layers | Expected result |
| --- | --- | --- |
| r0-boot | CPUs, AIC, PMGR, UART, watchdog, iBoot framebuffer | console on HDMI, shell prompt |
| r1-smc | + SMC | SMC probe lines, hwmon |
| r2-storage | + NVMe | `nvme0n1` and its partitions listed (read-only) |
| r3-usb | + rear Type-C (atc0/atc1) | USB keyboard works |
| r4-pcie | + PCIe (Wi-Fi/BT port 0, Ethernet port 2) | `eth0` (tg3) |
| r5-atc23 | + atc2 (front hub) / atc3 | front USB-C ports enumerate |

## Building

On an arm64 machine with Docker (the mini itself under macOS works):

```sh
tools/j773g-build.sh all      # image, source, config, DTBs, kernel, initramfs, m1n1
tools/j773g-build.sh check    # dt-schema validation of every rung
```

Artifacts land in `build/j773g/` (git-ignored). Source trees stay in the
Docker volume `j773g-src`.

## Rules this fork follows

- Development boots are RAM-only. Nothing touches the mini's internal disk,
  partitions or boot policy without the owner's explicit approval for that step.
- Apple firmware, raw ADT/ioreg dumps, macOS-extracted files and personal logs
  never enter the repository (`private/` is git-ignored).
- J713 speaker profiles and safety limits are never reused on the mini.

## Credits and licensing

Upstream integration and research by **studioxradio aka kb2uka**
([Omarchy-M4-Native](https://github.com/Kb2uka/Omarchy-M4-Native)); see
[docs/upstream-README.md](docs/upstream-README.md) for the full credits to
[Asahi Linux](https://asahilinux.org/), [m1n1](https://github.com/AsahiLinux/m1n1),
[Gravity Linux](https://github.com/GravityLinux), [Omarchy](https://github.com/basecamp/omarchy)
and others. J773g additions by Andrei Nita.

New files carry SPDX lines: device trees `GPL-2.0+ OR MIT`, kernel patches
`GPL-2.0-only`, scripts `MIT`, docs `CC-BY-4.0`. See [LICENSE.md](LICENSE.md),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/](LICENSES/).
No license here grants rights to Apple firmware, macOS or trademarks.
