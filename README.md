<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# OmarchyM4Mini — Omarchy on the base M4 Mac mini

Omarchy running natively on the base **M4 Mac mini — Mac16,10 / J773g / T8132**,
installed beside macOS: SSD boot, HDMI desktop, all ten CPU cores, GPU
acceleration, Wi-Fi, Ethernet, speaker and headphone jack.

> [!NOTE]
> **Two editions.** This public repository is the polished, functional
> version: only changes that have been tested on the mini land here.
> Day-to-day development happens in a **private, invite-only alpha** that is
> very unstable and changes without notice. If you want to help test it, ask
> [@andreinita21](https://github.com/andreinita21) for an invite.

> [!WARNING]
> This software changes how a Mac boots. Keep a recovery path: macOS stays
> installed, holding the power button opens the startup options, and a second
> Mac can DFU-revive the mini. Provided “AS IS”, without warranty of any kind.

Not sponsored, approved or endorsed by Omarchy / Basecamp, Asahi Linux,
Gravity Linux or Apple.

## Status (2026-10-26)

Omarchy boots from the internal SSD (m1n1 → U-Boot → Limine → UKI) and runs the
desktop on HDMI.

| Area | State | How |
| --- | --- | --- |
| Boot from the SSD, HDMI desktop | ✅ works | m1n1 built with `NO_DISPLAY`, `PHY_APPLE_DPTX=y` for the HDMI PHY ([docs/j773g-install.md](docs/j773g-install.md)) |
| All 10 CPU cores | ✅ works | kernel line `idle=nop nohlt arm64.nowfxt efi=noruntime`, no Plymouth `splash` ([NOTES.md](NOTES.md), "Setup 12") |
| Power-off and restart, RTC | ✅ works | Abbey PMU NVMEM cells + `apple,smc-reboot` / `apple,smc-rtc` in the DTB ([docs/j773g-poweroff.md](docs/j773g-poweroff.md)) |
| GPU acceleration (greeter, Hyprland, Wayland apps) | ✅ works | `asahi_m4` + `mesa-gravity-m4`, aquamarine with `AQ_NO_RENDERD_FALLBACK`, `j773g-gpu.service`; OpenGL ES 3.0, no Vulkan |
| Ethernet | ✅ works | BCM57762 (tg3) |
| Wi-Fi | ✅ works | BCM4388 (brcmfmac), firmware from macOS |
| Internal speaker | ✅ works, capped at −10 dB | protected T8132 speaker driver after the safety checklist ([docs/j773g-speaker-safety.md](docs/j773g-speaker-safety.md)) |
| 3.5 mm headphone jack | ✅ works, jack detect + auto switch | CS42L84 on MCA cluster 2 (`j773g-headphones.patch`) |
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

## Installing

There is no one-step installer yet. Omarchy goes onto the partitions Gravity
Linux's installer creates, without a USB drive:
[docs/j773g-install.md](docs/j773g-install.md).

## Layout

| Path | What |
| --- | --- |
| [START_HERE.md](START_HERE.md) | Project brief and safety rules |
| [PLAN.md](PLAN.md) | Board comparison, patch applicability, boot ladder, Phase 3 summary |
| [NOTES.md](NOTES.md) | One entry per setup step or boot attempt |
| [dts/t8132-j773g-ladder.dtsi](dts/t8132-j773g-ladder.dtsi) | Boot-ladder gates applied on top of GravityLinux's `t8132-j773g.dts` (bring-up history; audio off there) |
| [dts/asahi/](dts/asahi/) | Earlier layered tree on Asahi `77cb8f24c2` + T8132 patches (`BASE=asahi`) |
| [tools/j773g-build.sh](tools/j773g-build.sh), [tools/j773g/](tools/j773g/) | Docker build: GravityLinux `gravity-m4` kernel, ladder DTBs, busybox initramfs, m1n1 |
| [tools/j773g-boot.sh](tools/j773g-boot.sh) | One logged RAM-only boot of a ladder rung through the m1n1 proxy (run on the host) |
| [tools/j773g-adt-dump.sh](tools/j773g-adt-dump.sh) | Pull the live ADT into the git-ignored `private/` |
| [tools/j773g-install.sh](tools/j773g-install.sh), [tools/j773g/install-root.sh](tools/j773g/install-root.sh) | Omarchy onto the partitions Gravity's installer made ([docs/j773g-install.md](docs/j773g-install.md)) |
| [packaging/j773g/](packaging/j773g/) | The mini's Arch packages: `linux-gravity-m4` (kernel, DTB, speaker and headphone drivers), `m1n1-gravity`, `uboot-gravity`, `mesa-gravity-m4`, patched `aquamarine`, `omarchy-j773g` (glue, audio policy); built with [tools/j773g-pkg.sh](tools/j773g-pkg.sh) |
| [tools/j773g-image.sh](tools/j773g-image.sh), [tools/j773g/image-build.sh](tools/j773g/image-build.sh) | Omarchy disk image with the J773g packages, multicore line, GPU setup |
| [tools/j773g/trustcache.py](tools/j773g/trustcache.py) | Live CTRR/TrustCache probe over the m1n1 proxy |
| `docs/j773g-*.md` | Mini-specific notes |
| `*/j713/`, `docs/j713-*.md` | Shared T8132 platform layer (the M4 MacBook Air, J713) |

## How it got here

Bring-up went through a RAM-only boot ladder on GravityLinux's
hardware-tested J773g tree (`gravity-m4`): its own DTB as the control, then
CPUs/AIC/PMGR, SMC, NVMe, the four USB-C controllers and front hub, PCIe
(Wi-Fi and Ethernet), CPU frequency scaling and the native display. The rung
DTBs are in [dts/t8132-j773g-ladder.dtsi](dts/t8132-j773g-ladder.dtsi) and
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

Artifacts land in `build/j773g/` (git-ignored).

## Rules

- Experiments boot from RAM (m1n1 proxy) or from a non-default boot entry
  first. Nothing touches the mini's internal disk, partitions or boot policy
  without the owner's explicit approval for that step.
- Apple firmware, raw ADT/ioreg dumps, macOS-extracted files and personal logs
  never enter the repository (`private/` is git-ignored).
- Laptop speaker profiles and safety limits are never reused on the mini; the
  speaker runs only through the protected J773g driver, with its ceiling
  unchanged.

## Licensing

Maintained by **Andrei Nita** ([@andreinita21](https://github.com/andreinita21)).
Built on [Asahi Linux](https://asahilinux.org/), [m1n1](https://github.com/AsahiLinux/m1n1),
[Gravity Linux](https://github.com/GravityLinux) and [Omarchy](https://github.com/basecamp/omarchy).

There is no single license for the whole tree: files carry SPDX lines (device
trees `GPL-2.0+ OR MIT`, kernel patches `GPL-2.0-only`, scripts `MIT`, docs
`CC-BY-4.0`). See [LICENSE.md](LICENSE.md),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/](LICENSES/).
No license here grants rights to Apple firmware, macOS or trademarks.
