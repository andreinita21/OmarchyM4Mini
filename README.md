<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# OmarchyM4Mini — Linux bring-up on the base M4 Mac mini

> [!WARNING]
> **Experimental.** Omarchy runs on the base **M4 Mac mini — Mac16,10 / J773g /
> T8132** installed beside macOS, but this is a bring-up project, not a
> release: there is no one-step installer yet, and it can cause data loss, boot
> failures or hardware damage. Keep a working recovery path (macOS stays
> installed; hold the power button for the startup options; DFU revive from a
> second Mac). Provided “AS IS”, without warranty of any kind.

This is a fork of [Kb2uka/Omarchy-M4-Native](https://github.com/Kb2uka/Omarchy-M4-Native),
the experimental Omarchy/Asahi bring-up for the 13-inch M4 MacBook Air
(Mac16,12 / J713). The two machines share the T8132 SoC, so CPU bring-up, AIC,
PMGR, NVMe, SMC basics and the GPU carry over. The board is different: no
internal panel (HDMI and Thunderbolt only), no internal keyboard or trackpad,
Gigabit Ethernet, four USB/Type-C controllers instead of two, and a different
speaker. This fork adds the J773g pieces in new files next to the J713 ones.

**There is no one-step installer for the mini yet.** Omarchy is put onto the
partitions Gravity Linux's installer creates ([docs/j773g-install.md](docs/j773g-install.md)).
Upstream's J713 installer refuses other boards on purpose; do not use it here.

Not an official release. Not sponsored, approved or endorsed by Omarchy /
Basecamp, Asahi Linux, Gravity Linux, Apple, or Kb2uka.

## Status (2026-10-17)

Omarchy boots from the internal SSD (m1n1 → U-Boot → Limine → UKI) and runs the
desktop on HDMI.

| Area | State | How |
| --- | --- | --- |
| Boot from the SSD, HDMI desktop | ✅ works | Gravity's m1n1 built with `NO_DISPLAY`, `PHY_APPLE_DPTX=y` for the HDMI PHY ([docs/j773g-install.md](docs/j773g-install.md)) |
| All 10 CPU cores | ✅ works | kernel line `idle=nop nohlt arm64.nowfxt efi=noruntime`, no Plymouth `splash` ([NOTES.md](NOTES.md), "Setup 12") |
| Power-off and restart, RTC | ✅ works | Abbey PMU NVMEM cells + `apple,smc-reboot` / `apple,smc-rtc` in the DTB ([docs/j773g-poweroff.md](docs/j773g-poweroff.md)) |
| GPU acceleration (greeter, Hyprland, Wayland apps) | ✅ works | `asahi_m4` + GravityLinux Mesa (`mesa-gravity-m4`), aquamarine with `AQ_NO_RENDERD_FALLBACK`, `j773g-gpu.service`; OpenGL ES 3.0, no Vulkan |
| Ethernet | ✅ works | BCM57762 (tg3) |
| Wi-Fi | ✅ works | BCM4388 (brcmfmac), firmware from macOS |
| Internal speaker | ✅ works, capped at −10 dB | Gravity's protected T8132 driver after the safety checklist ([docs/j773g-speaker-safety.md](docs/j773g-speaker-safety.md)) |
| 3.5 mm headphone jack | ✅ works, jack detect + auto switch | CS42L84 on MCA cluster 2, upstream's J713 card ported (`j773g-headphones.patch`) |
| USB keyboard and mouse | ✅ works | Logitech receiver on a USB-C port; other USB devices not tested yet |
| Video out over USB-C / Thunderbolt | ❌ not yet | next target (native DP alt-mode) |
| Headset microphone | untested | |
| Bluetooth | seen working, not tested | a paired Bluetooth audio device appeared in PipeWire |

Known limitations: the Limine boot menu is invisible (HDMI lights only once
the kernel's display driver starts); the GPU is OpenGL ES 3.0 only; the
speaker is quieter than in macOS by design; the patched `aquamarine` and
`mesa-gravity-m4` are pinned with `IgnorePkg`, so a Hyprland update that
needs a newer aquamarine waits until the patch is carried forward.

The running log is [NOTES.md](NOTES.md).

## Layout

| Path | What |
| --- | --- |
| [START_HERE.md](START_HERE.md) | Project brief and safety rules |
| [PLAN.md](PLAN.md) | J713-vs-J773g comparison, patch applicability, boot ladder, Phase 3 summary |
| [NOTES.md](NOTES.md) | One entry per setup step or boot attempt |
| [dts/t8132-j773g-ladder.dtsi](dts/t8132-j773g-ladder.dtsi) | Boot-ladder gates applied on top of GravityLinux's `t8132-j773g.dts` (bring-up history; audio off there) |
| [dts/asahi/](dts/asahi/) | Earlier layered tree on Asahi `77cb8f24c2` + upstream T8132 patches (`BASE=asahi`) |
| [tools/j773g-build.sh](tools/j773g-build.sh), [tools/j773g/](tools/j773g/) | Docker build: GravityLinux `gravity-m4` kernel, ladder DTBs, busybox initramfs, m1n1 |
| [tools/j773g-boot.sh](tools/j773g-boot.sh) | One logged RAM-only boot of a ladder rung through the m1n1 proxy (run on the host) |
| [tools/j773g-adt-dump.sh](tools/j773g-adt-dump.sh) | Pull the live ADT into the git-ignored `private/` |
| [tools/j773g-install.sh](tools/j773g-install.sh), [tools/j773g/install-root.sh](tools/j773g/install-root.sh) | Omarchy onto the partitions Gravity's installer made, no USB drive ([docs/j773g-install.md](docs/j773g-install.md)) |
| [packaging/j773g/](packaging/j773g/) | The mini's Arch packages: `linux-gravity-m4` (kernel, DTB, speaker and headphone drivers), `m1n1-gravity`, `uboot-gravity`, `mesa-gravity-m4`, patched `aquamarine`, `omarchy-j773g` (glue, audio policy); built with [tools/j773g-pkg.sh](tools/j773g-pkg.sh) |
| [tools/j773g-image.sh](tools/j773g-image.sh), [tools/j773g/image-build.sh](tools/j773g/image-build.sh) | Omarchy disk image with the J773g packages, multicore line, GPU setup |
| [tools/j773g/trustcache.py](tools/j773g/trustcache.py) | Live CTRR/TrustCache probe over the m1n1 proxy |
| `docs/j773g-*.md` | Mini-specific notes |
| everything else | Upstream's J713 work, unchanged; its front page is now [docs/upstream-README.md](docs/upstream-README.md) |

## How it got here

Bring-up went through a RAM-only boot ladder on GravityLinux's
hardware-tested J773g tree (`gravity-m4`, whose J773g tree had booted Fedora
on this machine): Gravity's own DTB as the control, then CPUs/AIC/PMGR, SMC,
NVMe, the four USB-C controllers and front hub, PCIe (Wi-Fi and Ethernet),
CPU frequency scaling and the native display. The rung DTBs are in
[dts/t8132-j773g-ladder.dtsi](dts/t8132-j773g-ladder.dtsi) and
[tools/j773g-boot.sh](tools/j773g-boot.sh) boots one through the m1n1 proxy.
Omarchy then went onto the SSD as packages on Omarchy's official Apple Silicon
platform ([docs/j773g-phase3-plan.md](docs/j773g-phase3-plan.md)).

## Building

On an arm64 machine with Docker (the mini itself under macOS works):

```sh
tools/j773g-pkg.sh image      # Arch Linux ARM build container
tools/j773g-pkg.sh all        # the J773g packages -> build/j773g/pkgs/
tools/j773g-image.sh          # Omarchy disk image with them
tools/j773g-build.sh all      # bring-up kit: ladder DTBs, kernel, initramfs, m1n1
```

Artifacts land in `build/j773g/` (git-ignored). Installing onto the mini:
[docs/j773g-install.md](docs/j773g-install.md).

## Rules this fork follows

- Experiments boot from RAM (m1n1 proxy) or from a non-default boot entry
  first. Nothing touches the mini's internal disk, partitions or boot policy
  without the owner's explicit approval for that step.
- Apple firmware, raw ADT/ioreg dumps, macOS-extracted files and personal logs
  never enter the repository (`private/` is git-ignored).
- J713 speaker profiles and safety limits are never reused on the mini; the
  speaker runs only through Gravity's protected J773g driver, with its ceiling
  unchanged.

## Credits and licensing

Upstream integration and research by **studioxradio aka kb2uka**
([Omarchy-M4-Native](https://github.com/Kb2uka/Omarchy-M4-Native)); see
[docs/upstream-README.md](docs/upstream-README.md) for the full credits to
[Asahi Linux](https://asahilinux.org/), [m1n1](https://github.com/AsahiLinux/m1n1),
[Gravity Linux](https://github.com/GravityLinux) (whose J773g kernel and device tree this fork now builds on), [Omarchy](https://github.com/basecamp/omarchy)
and others. The mini's kernel, device tree, m1n1, U-Boot, Mesa and protected
speaker driver come from Gravity Linux; the headphone card driver and its
audio policy are ported from Omarchy-M4-Native's J713 work. J773g additions
by Andrei Nita.

New files carry SPDX lines: device trees `GPL-2.0+ OR MIT`, kernel patches
`GPL-2.0-only`, scripts `MIT`, docs `CC-BY-4.0`. See [LICENSE.md](LICENSE.md),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/](LICENSES/).
No license here grants rights to Apple firmware, macOS or trademarks.
