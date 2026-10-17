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
| Boot ladder on GravityLinux's hardware-tested J773g tree, offline-validated (dtc + dt-schema) | done — [dts/](dts/) |
| Containerised kernel (GravityLinux gravity-m4) / DTB / initramfs / m1n1 build | done — [tools/j773g-build.sh](tools/j773g-build.sh) |
| Research: ports, front hub, PCIe power, Wi-Fi chip, stub install | done — [docs/j773g-research.md](docs/j773g-research.md) |
| m1n1 stub on the mini (Gravity Linux alpha installed and booted, 2026-10-17) | done; live ADT dump through m1n1 proxy: next |
| First RAM-only boot to a busybox shell on HDMI | not started |
| Phase 3: Omarchy on the mini, on Omarchy's official Apple Silicon platform with Gravity-based kernel/m1n1/U-Boot packages | planned — [docs/j773g-phase3-plan.md](docs/j773g-phase3-plan.md) |

The running log is [NOTES.md](NOTES.md); the next hardware session follows
[docs/j773g-home-day-checklist.md](docs/j773g-home-day-checklist.md).

## Layout

| Path | What |
| --- | --- |
| [START_HERE.md](START_HERE.md) | Project brief and safety rules |
| [PLAN.md](PLAN.md) | J713-vs-J773g comparison, patch applicability, boot ladder, Phase 3 summary |
| [NOTES.md](NOTES.md) | One entry per setup step or boot attempt |
| [dts/t8132-j773g-ladder.dtsi](dts/t8132-j773g-ladder.dtsi) | Boot-ladder gates applied on top of GravityLinux's `t8132-j773g.dts`; audio always off |
| [dts/asahi/](dts/asahi/) | Earlier layered tree on Asahi `77cb8f24c2` + upstream T8132 patches (`BASE=asahi`) |
| [tools/j773g-build.sh](tools/j773g-build.sh), [tools/j773g/](tools/j773g/) | Docker build: GravityLinux `gravity-m4` kernel, ladder DTBs, busybox initramfs, m1n1 |
| [tools/j773g-boot.sh](tools/j773g-boot.sh) | One logged RAM-only boot of a ladder rung through the m1n1 proxy (run on the host) |
| [tools/j773g-adt-dump.sh](tools/j773g-adt-dump.sh) | Pull the live ADT into the git-ignored `private/` |
| [tools/j773g-install.sh](tools/j773g-install.sh), [tools/j773g/install-root.sh](tools/j773g/install-root.sh) | Omarchy onto the partitions Gravity's installer made, no USB drive ([docs/j773g-install.md](docs/j773g-install.md)) |
| `docs/j773g-*.md` | Mini-specific notes |
| everything else | Upstream's J713 work, unchanged; its front page is now [docs/upstream-README.md](docs/upstream-README.md) |

## The boot ladder

The kernel and board device tree come from [GravityLinux](https://github.com/GravityLinux/linux)
(`gravity-m4`), whose J773g tree has booted Fedora on this machine. Each rung
turns on one more subsystem group; audio stays off until a mini-specific
speaker safety profile has been reviewed:

| Rung | Adds | Expected result |
| --- | --- | --- |
| stock | Gravity's own DTB (control) | console on HDMI, shell |
| g0-boot | CPUs, AIC, PMGR, UART, watchdog, iBoot framebuffer | console on HDMI, shell prompt |
| g1-smc | SMC | SMC probe lines, hwmon |
| g2-storage | NVMe | `nvme0n1` and its partitions listed (read-only) |
| g3-usb | all four USB-C controllers + front hub | USB keyboard works |
| g4-pcie | PCIe (Wi-Fi/BT port 0, Ethernet port 2) | `eth0` (tg3) |
| g5-cpufreq | CPU frequency scaling | stable under load |
| g6-display | DCP native display | appledrm drives HDMI |

## Building

On an arm64 machine with Docker (the mini itself under macOS works):

```sh
tools/j773g-build.sh all      # image, source, config, DTBs, kernel, initramfs, m1n1 (Gravity base)
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
[Gravity Linux](https://github.com/GravityLinux) (whose J773g kernel and device tree this fork now builds on), [Omarchy](https://github.com/basecamp/omarchy)
and others. J773g additions by Andrei Nita.

New files carry SPDX lines: device trees `GPL-2.0+ OR MIT`, kernel patches
`GPL-2.0-only`, scripts `MIT`, docs `CC-BY-4.0`. See [LICENSE.md](LICENSE.md),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/](LICENSES/).
No license here grants rights to Apple firmware, macOS or trademarks.
