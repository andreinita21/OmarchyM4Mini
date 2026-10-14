<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# J773g packages for Omarchy's Apple Silicon platform

Arch packages that make Omarchy's official `aarch64-apple` platform
(omacom/omarchy-mac-pkgs: `omarchy-mac`, `omarchy-mac-boot`) boot the base M4
Mac mini. Plan: [docs/j773g-phase3-plan.md](../../docs/j773g-phase3-plan.md).
They replace exactly the pieces Omarchy builds for M1/M2 and nothing else.

| Package | Replaces | Source |
|---|---|---|
| `linux-gravity-m4` (+ `-headers`) | `linux-aurora` / `linux-asahi` (provides `linux-asahi`) | GravityLinux/linux `gravity-m4` @ 4fc326f6c2 (7.1.13); config = asahi-alarm's linux-asahi 7.1.13 + `j773g.fragment` |
| `m1n1-gravity` | `m1n1-aurora` / `m1n1` (provides `m1n1=1.6.1`) | GravityLinux/bootloader @ 7243b815c4 + its artwork submodule + kb2uka's `dockchannel-tx-bound.patch` (upstream #82: bounded console waits, so a FIFO nobody drains cannot hang m1n1 on the logo) |
| `uboot-gravity` | `uboot-asahi` (provides it) | AsahiLinux/u-boot asahi-v2026.07-2 + asahi-alarm/Omarchy patches + GravityLinux's nine T8132 patches |
| `omarchy-j773g` | — (glue) | this directory: `asahi,efi-system-partition` from the Gravity stage-1 property, J773g-only DTB in stage 2, `omarchy-mac-kernel` shim |

Build on the mini (Docker Desktop, arm64):

```sh
tools/j773g-pkg.sh image      # Arch Linux ARM container (downloads the rootfs once)
tools/j773g-pkg.sh all        # -> build/j773g/pkgs/*.pkg.tar.zst
```

Nothing here is signed or published; the image builder installs the files
directly. Audio drivers for the internal speaker are compiled out
(START_HERE rule 6). The kernel's Rust parts pin toolchain 1.93.1 like
Omarchy's linux-aurora; bindgen comes from Arch Linux ARM.
