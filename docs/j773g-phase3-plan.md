<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Phase 3 plan — Omarchy on the M4 Mac mini (J773g), Gravity kernel

Status: **plan, 2026-10-14** (Fable 5.1 / high). Nothing below has run on
hardware. Phase 3 starts only after the Phase 2 ladder (PLAN.md §5) has
reached at least `g6-display`, with `g2`–`g4` (NVMe, USB keyboard,
Ethernet) passing. Every step that writes the mini's disk needs Andrei's
explicit approval for that step (START_HERE rule 1).

## 0. Summary

Omarchy upstream now has an official Apple Silicon platform. Phase 3 reuses
that stack unchanged and swaps only the three hardware pieces the M4 mini
needs: the kernel package, m1n1 and U-Boot, all built from the Gravity
sources this repo already pins. Everything else (desktop, settings, Mac
packages, Limine boot, updates) comes from Omarchy's own `edge` repository.
The result is a normal Omarchy install that updates with `omarchy update`,
not a fork.

## 1. What exists today (checked 2026-10-14)

### 1.1 Omarchy upstream has an Apple Silicon platform

Merged into `basecamp/omarchy` on 2026-10-10 (PR #14431, "Converge
omarchy-mac and omarchy-mx-mac into upstream Omarchy"). Facts that matter:

| Item | Value |
|---|---|
| Platform name | `aarch64-apple` (`omarchy-hw-platform` reads the DT root `compatible` prefix `apple,`) |
| Package set | `install/omarchy-base.packages` + `omarchy-aarch64.packages` (zram-generator) + `omarchy-aarch64-apple.packages` (`omarchy-mac`, `omarchy-mac-boot`, asahi-bless, avd-fw, libva-v4l2_request-avd, widevine, wf-recorder) |
| Pacman template | `default/pacman/aarch64-apple/`: `[omarchy]` = `https://pkgs.omarchy.org/edge/$arch`, then `[asahi-alarm]`, then Arch Linux ARM via `arm-mirror.omarchy.org`. **Edge channel only** on aarch64 |
| Mac packages (omacom/omarchy-mac-pkgs) | `omarchy-mac` 0.1.4 (Wi-Fi backend, mic, speaker safety presets, platform data) and `omarchy-mac-boot` 20261010 (initramfs hooks, vendor firmware from the ESP, in-place LUKS, first boot, Limine activation, boot check, DT overlays) |
| Boot chain | Apple firmware → m1n1 stage 1 → `<ESP>/m1n1/boot.bin` (m1n1 + DTBs + gzipped U-Boot + `/etc/m1n1.conf` lines) → U-Boot → **Limine** at `EFI/BOOT/BOOTAA64.EFI` → UKI `omarchy_<kernel>.efi` on the ESP → btrfs root. GRUB is gone from fresh images |
| Kernel | `linux-aurora` 7.1.12.aurora2 (aurora-silicon/linux, an Asahi fork; 16K pages, Rust, DRM_ASAHI). `omarchy-mac-kernel` accepts exactly `linux-asahi` or `linux-aurora` |
| m1n1 / U-Boot | `m1n1-aurora` 1.6.1 (provides `m1n1`), `uboot-asahi` 2026.07 |
| Image producer | `omacom/omarchy-mac-installer` `image-builder/`: ALARM rootfs → `omarchy-settings` → image manifest `/var/lib/omarchy/image/target` → runtime + package lists → kernel/m1n1/U-Boot → `omarchy-apply-system --defer-provisioning --first-install` → `mkinitcpio -P`, `update-m1n1` (`LC_ALL=C`), Limine via `omarchy-lifecycle-dispatch setup-boot` → seal → zip + `installer_data.json` (EFI 500 MB, Boot 2 GB, Root 32 GB expandable). Its policy refuses `linux-asahi`, Asahi `m1n1` and `grub` |
| Installer | macOS app around the Asahi installer v0.9.2 engine. Catalog: all 34 M1/M2/M3 boards; **M4 refused**: "M4 and later Macs are not supported" (`scripts/supported-models.json`) |
| Status | Mac manual: no public release yet; packages on `edge`, qualified on M1 Pro / M2 Max first. M3 ships with llvmpipe until its GPU driver lands |

Everything Omarchy's Mac stack needs from the hardware side is therefore a
**kernel package with device trees, an m1n1 and a U-Boot that boot the
board**. The boot package even anticipates new SoCs (its DT-overlay
mechanism and the `-ARCH` kernel convention).

### 1.2 Upstream Omarchy-M4-Native (kb2uka, J713)

A separate design: Arch ARM root, `boot.bin` = m1n1 + kernel + DTB +
initramfs with no U-Boot/Limine, J713-only root-identity installer patches,
and its own `[omarchy-m4]` channel for kernel/DTB updates. It predates the
official platform and is coupled to J713 manifests (video/audio
qualification hashes, trackpad options). Not the base for the mini.

### 1.3 Gravity Linux (the kernel base, PLAN.md §3)

Fedora 44 KDE remix for J773g only. Installed layout from
`cdn.gravitylinux.org/installer/installer_data.json` (release
`gravity-20260920`): EFI 500 MB (firmware + installer data), Boot 1 GB
ext4 (`/boot`, GRUB BLS), Root ≥16 GB btrfs (`@root`, `home`). Stage 2 =
`update-m1n1`: `m1n1.bin` + `t6*.dtb t81*.dtb` + gzipped
`u-boot-nodtb.bin` + `m1n1.conf` lines; U-Boot → shim/GRUB. Gravity's
pieces we reuse:

- **U-Boot:** `GravityLinux/u-boot` (2026.07 + 9 patches: T8132 memory map
  and DRAM banks, T8132 ANS2 NVMe, ESP discovery on T8132, Bluetooth BTBF
  and Wi-Fi calibration from `vendorfw/u-boot/brcm/` on the ESP). It reads
  the `gravity,efi-system-partition` chosen property, not `asahi,…`.
- **m1n1:** `GravityLinux/bootloader` (built in this repo as
  `build/j773g/m1n1-gravity/`), needed for DCP 26.6.2 compatibility and the
  T8132 GPU platform data.
- **Firmware:** `gravity-fwextract` writes `vendorfw/firmware.cpio` plus the
  BT/Wi-Fi calibration files to the ESP. Omarchy's `omarchy-vendorfw`
  initcpio hook unpacks the same `firmware.cpio` layout. The V-u NVRAM bug
  (`docs/j773g-gravity-issue-drafts.md`) carries over until fixed.

### 1.4 Arch Linux ARM availability

Checked on archlinuxarm.org for aarch64: hyprland 0.56.2, quickshell
0.3.2, uwsm 0.27, sddm 0.21, chromium 153, xdg-desktop-portal-hyprland,
hyprpicker, hyprsunset, wireplumber, foot. Omarchy's `edge/aarch64` db
(fetched 2026-10-14) carries `omarchy` 4.0.4-2, `omarchy-settings` 4.0.4-6,
`omarchy-mac`, `omarchy-mac-boot`, `linux-aurora`, `m1n1-aurora`,
`limine-mkinitcpio-hook`, `limine-snapper-sync`, `quickshell`, `hyprland`,
`omarchy-chromium`, mise and the rest of the desktop set. `limine` itself
comes from Arch Linux ARM.

## 2. Decision: route O (official Omarchy Mac stack, M4 hardware packages)

| Route | What | Verdict |
|---|---|---|
| **O** | Official Omarchy `aarch64-apple` platform + `omarchy-mac`/`omarchy-mac-boot` + Limine, with three J773g packages replacing kernel, m1n1 and U-Boot | **Chosen.** Smallest delta, normal `omarchy update`, the platform explicitly expects hardware to come as packages. M3's "llvmpipe first" precedent covers our GPU gap |
| K | kb2uka's `boot.bin` + root-identity installer + `[omarchy-m4]` channel, ported to J773g | No U-Boot/Limine, J713-coupled manifests, parallel to the official stack. Only as a fallback if U-Boot never boots T8132 under Limine |
| F | Hyprland/Omarchy configs on the Gravity Fedora root | Not Omarchy (Arch-only packages, updater, settings). Rejected |

Risks accepted with route O: Omarchy aarch64 is `edge` only and still
renaming things (the image builder still writes `platform=apple-silicon`
for an older runtime); U-Boot+Limine on T8132 is untested (Gravity boots
U-Boot→GRUB, Omarchy boots U-Boot→Limine on M1/M2, nobody has done both on
M4); the kernel package name is checked by `omarchy-mac-kernel`.

## 3. The J773g package set (new, `packaging/j773g/`, MIT PKGBUILDs)

Built for aarch64 with `makepkg` inside an Arch Linux ARM container on the
mini (Docker, same volume scheme as `tools/j773g-build.sh`); never compiled
on the host. Signed by nothing: these are local packages installed into the
image by file, exactly as the official image builder installs its candidate
set by `omarchy-candidates/` name.

| Package | Source | Provides / conflicts | Contents |
|---|---|---|---|
| `linux-gravity-m4` (+`-headers`) | GravityLinux/linux `gravity-m4` @ `4fc326f6c2` (7.1.13), as `tools/j773g/inner-build.sh` pins | `provides=(linux-asahi=… WIREGUARD-MODULE)`, `conflicts=(linux-asahi linux-aurora)` | `/usr/lib/modules/<ver>-ARCH/{vmlinuz,pkgbase,dtbs/*.dtb}` + modules, the `linux-aurora` PKGBUILD layout. `CONFIG_LOCALVERSION="-ARCH"` so update-m1n1's default DTB glob matches. Config = Aurora's `config` as the distro baseline (16K, Rust) with our `kernel.fragment` decisions on top: the full Apple stack built in, `DRM_ASAHI_M4=m` (Gravity's own choice), speaker/TAS2764/MCA drivers **=n**, brcmfmac built in, pstore |
| `m1n1-gravity` | GravityLinux/bootloader @ `7243b815c4` (`build/j773g/m1n1-gravity/`) | `provides=(m1n1=1.6.1)`, `conflicts=(m1n1 m1n1-aurora)` | `/usr/lib/asahi-boot/m1n1.bin` (asahi-scripts' default `SOURCE`) |
| `uboot-gravity` | GravityLinux/u-boot `main` (2026.07 + Gravity's T8132 patches, `apple_m1` defconfig) | `provides=(uboot-asahi)`, `conflicts=(uboot-asahi)` | `/usr/lib/asahi-boot/u-boot-nodtb.bin` |
| `omarchy-j773g` (small) | this repo | — | `/etc/m1n1.conf` line below; `/etc/default/update-m1n1` drop-in limiting `DTBS` to `t8132-j773g.dtb`; `/etc/modprobe.d` nothing yet; a pacman hook is **not** needed (omarchy-mac-boot already rebuilds the UKI and `boot.bin`) |

Two integration points need glue, both small:

1. **ESP property.** Gravity's stage 1 passes
   `chosen.gravity,efi-system-partition=<uuid>`; Omarchy's hooks
   (`omarchy-vendorfw`, asahi-scripts `mount_sys_esp`) read
   `asahi,efi-system-partition`. `update-m1n1` appends any `chosen.*=*` line
   from `/etc/m1n1.conf` to stage 2, so `omarchy-j773g`'s first-boot script
   writes `chosen.asahi,efi-system-partition=<same uuid>` into
   `/etc/m1n1.conf` (read from `/proc/device-tree/chosen/gravity,…`) and
   runs `update-m1n1` once. U-Boot (Gravity fork) keeps using the
   `gravity,` property. Both exist after that boot; no script is patched.
2. **Kernel package name.** `omarchy-mac-kernel` matches
   `^linux-(asahi|aurora)$`. Proper fix: a PR to omacom/omarchy-mac-pkgs
   making it accept any installed package that **provides** `linux-asahi`
   (one `pacman -Qq` + `-Qi` provides check). Until merged, `omarchy-j773g`
   ships a `/usr/local/bin/omarchy-mac-kernel` shim that prints
   `linux-gravity-m4` (PATH order wins). Draft in
   `docs/j773g-omarchy-issue-drafts.md` (to write; Andrei posts).

Not packaged in Phase 3's first iteration: Mesa. The platform package
requires `vulkan-asahi` from asahi-alarm (M1/M2 driver); on the mini the
desktop renders with llvmpipe, exactly like official M3 Macs today. Gravity's
`GravityLinux/mesa` fork (RPM spec in GravityLinux/packages) is the source
for a later `mesa-gravity-m4` package once rung `g8-gpu` proves
`DRM_ASAHI_M4` on this unit.

## 4. The image (`tools/j773g-image.sh`, offline, on the mini in Docker)

A trimmed, unsigned copy of the official producer's build order (its
`candidate_set` policy refuses any kernel but Aurora, so we cannot call it
directly; we mirror the steps so the result is what `omarchy-mac-boot`
expects):

1. Unpack `ArchLinuxARM-aarch64-latest.tar.gz`; pacstrap `base` +
   `omarchy-keyring` + `asahi-alarm-keyring`; install Omarchy's
   `default/pacman/aarch64-apple/pacman-edge.conf` + mirrorlist.
2. `pacman -S omarchy-settings` alone (its platform guard must be resident
   before any platform package).
3. Write `/var/lib/omarchy/image/target` (`format=1`,
   `platform=aarch64-apple`).
4. Install `omarchy` + `$(omarchy-pkg-defaults aarch64-apple)` minus nothing
   (asahi-bless, avd-fw etc. are harmless on M4), then our four packages by
   file, then `limine-mkinitcpio-hook`, `alsa-ucm-conf-asahi`,
   `asahi-audio` (as the official build does; the audio preset is a no-op
   while the speaker drivers are compiled out).
5. `omarchy-apply-system --defer-provisioning --first-install` in the
   chroot (hardware steps are queued for first boot via the manifest).
6. `/etc/default/grub` command line = Omarchy's `quiet splash
   plymouth.ignore-serial-consoles` **plus our ladder-proven options from
   PLAN.md §5** (whatever `g6` needed; drop `nosmp`/`idle=nop` only if the
   ladder showed they are unnecessary). `mkinitcpio -P`; `LC_ALL=C
   update-m1n1` against a scratch `boot.bin`; `omarchy-lifecycle-dispatch
   setup-boot image-first-boot`; arm first boot (`omarchy-mac-boot`'s own
   `arm` command).
7. Seal into `root.img` (btrfs, Omarchy's subvolume layout: `@`, `@home`,
   `@log`, `@pkg`, `.snapshots`, sealed `@factory`), `boot.img` only if we
   keep a separate `/boot` (Limine does not need one; see §5), and an
   `esp/` tree (`EFI/BOOT/BOOTAA64.EFI`, `EFI/Linux/omarchy_linux-gravity-m4.efi`,
   `limine.conf`, `m1n1/boot.bin`).
8. QEMU smoke test (generic virt, 16K kernel): systemd reaches
   `multi-user.target`, `pacman -Qk` clean, `omarchy-hw-platform` answers
   `aarch64-apple` from the manifest. This proves the root, not the Mac.

Size: Omarchy base ≈ 9–11 GB installed; `root.img` ≥ 24 GB, expandable on
first boot (`x-systemd.growfs`). Build time on the mini: ~30–40 min
(downloads dominate).

## 5. Getting it onto the mini (the disk-touching part)

Gravity (route A) will already be on the disk with stub + EFI + Boot + Root.
Two ways to install our image; both keep macOS and the Gravity stub, and
both need approval per step:

| Option | How | When |
|---|---|---|
| **5a replace in place** | From Gravity (or the RAM busybox with NVMe + USB): back up `m1n1/boot.bin` → `boot.bin.gravity`; write `root.img` over Gravity's **Root** partition (`dd` to the partition only, never the disk); copy `esp/` onto the EFI partition (Limine, UKI, `limine.conf`, new `m1n1/boot.bin`); leave **Boot** (1 GB ext4) unused or mount it as `/boot` for `limine-snapper-sync`'s needs. First boot runs Omarchy's owner setup | **First iteration.** No new stub, no partition-table change. Undo = restore `boot.bin.gravity` and reflash Gravity's root |
| 5b our own installer package | Gravity's installer accepts a local `installer_data.json` (`scripts/bootstrap.sh` is "for a local server"). Serve our zip (`esp/`, `root.img`) with a template `EFI 500 MB + Root (expand)`; the installer does stub, firmware, partitions and stage 1 | Later, for a repeatable install or a second machine. Replaces §5a's manual copy |

Disk budget: Omarchy root ≥ 24 GB + ESP; the Gravity install cannot stay
alongside within the 60–80 GB planned in the home-day checklist, so §5a
replaces Gravity. If Andrei wants to keep Gravity bootable, give Linux
≥ 110 GB at install time and use §5b into free space with its own EFI.

**Before any of that: rung `u0`.** Boot our kernel from RAM (`tools/j773g-boot.sh u0`:
the packaged kernel, the image's own `mkinitcpio` initramfs and Limine's
`root=UUID=… rootflags=subvol=@` line, kit made by `tools/j773g-disk.sh
compose`) against the **Omarchy root written to a USB SSD** (`tools/j773g-disk.sh
write <disk>`) on a rear port. That validates the whole userland on the real
mini (Hyprland on simpledrm or DCP, SDDM, keyboard, Ethernet, `omarchy
update` against edge) with zero internal-disk writes. Needs a USB drive
≥ 32 GB and rung `g3-usb` passing.

## 6. Step table

| # | Step | Where | Model | Approval | Depends on |
|---|---|---|---|---|---|
| P3.1 | PKGBUILDs: `linux-gravity-m4`, `m1n1-gravity`, `uboot-gravity`, `omarchy-j773g`; ALARM build container; build into `build/j773g/pkgs/` | mini (Docker) | Opus / medium | no | **done 2026-10-14** (`packaging/j773g/`) |
| P3.2 | `tools/j773g-image.sh` (§4) + QEMU smoke test; `docs/j773g-image.md` | mini (Docker) | Opus / medium | no | **done 2026-10-14**: image boots in QEMU to the login prompt |
| P3.3 | Upstream drafts: omarchy-mac-pkgs `omarchy-mac-kernel` provides check; omarchy-mac-installer catalog note for `apple,j773g`; Gravity issues (already drafted) | repo | Opus / medium | Andrei posts | drafted 2026-10-14 (`docs/j773g-omarchy-issue-drafts.md`) |
| P3.4 | Rung `u0`: Omarchy root on USB, kernel from RAM | mini + host | Opus / medium (Fable if stuck) | USB drive only | ladder ≥ g6, P3.2. **Tooling done 2026-10-14**: `tools/j773g-disk.sh compose` / `write <disk>`, `tools/j773g-boot.sh u0` ([j773g-image.md](j773g-image.md), rung u0); the hardware run is pending |
| P3.5 | §5a: write `root.img`, ESP files, stage 2 swap; `boot.bin.gravity` kept | mini | Opus / medium | **yes, per command** | P3.4 green |
| P3.6 | First boot: owner setup, `omarchy-apple-silicon-boot-check`, `omarchy update`, shutdown test (g7 PMU nodes are in our DTB) | mini | Opus / medium | no | P3.5 |
| P3.7 | Later: `mesa-gravity-m4` (after g8), Wi-Fi V=a NVRAM override in `/usr/lib/firmware/brcm/` (kernel searches it before `vendor/`), Bluetooth (Gravity's U-Boot already supplies BTBF from the ESP), audio with the reviewed limiter | mini | Opus; Fable for new DT nodes | audio: yes | P3.6 |

Model budget: this plan is the Fable part. P3.1–P3.6 are packaging and
scripting, Opus 5.5 / medium. Escalate to Fable only for a U-Boot or Limine
hang on T8132 that Opus cannot read in 2–3 attempts (START_HERE §4).

## 7. Known unknowns

- **U-Boot → Limine on T8132.** Gravity proves U-Boot→GRUB, Omarchy proves
  U-Boot→Limine on M1/M2. If Limine's arm64 EFI misbehaves on Gravity's
  U-Boot, fallback 1 is GRUB (asahi-alarm's `grub` package still exists;
  `omarchy-mac-boot` keeps a GRUB compatibility path), fallback 2 is route K.
- **Display handoff.** Omarchy's greeter waits up to 10 s for appledrm to
  replace the boot framebuffer; on the mini that is HDMI via DCPEXT. Rung
  `g6` tells us whether DCP works at all; until then the image must boot
  with simpledrm (`display` group disabled) and llvmpipe.
- **Kernel/DT update path.** Omarchy's `omarchy-mac-boot` rebuilds
  `boot.bin` and the UKI on kernel updates; our kernel package is local, so
  updates are `pacman -U` of a new build. A small `[omarchy-j773g]` file
  repo on the ESP or a GitHub release is the natural next step, not needed
  for first light.
- **16K pages + Chromium/Electron.** Aurora is 16K too, so ALARM's Chromium
  and Omarchy's wrappers already live with it.
- **Gravity firmware bug.** The installer's V-u NVRAM lands in
  `vendorfw/firmware.cpio`; Ethernet first, Wi-Fi fix in P3.7.

## 8. Decisions for Andrei

1. Route O (official Omarchy Mac platform) over kb2uka's route K — confirm.
2. A USB SSD/stick ≥ 32 GB for rung `u0`.
3. Replace Gravity on disk (§5a) vs. keep both (needs ≥ 110 GB for Linux
   and §5b).
4. Whether to post the three upstream drafts (Omarchy Mac packages,
   Omarchy Mac installer, Gravity).

## Sources

- https://github.com/basecamp/omarchy (install/*.packages, default/pacman/aarch64-apple, docs/file-layout.md, docs/update-process.md, AGENTS.md "Platforms"; PR #14431)
- https://github.com/omacom/omarchy-mac-pkgs (omarchy-mac/README.md, omarchy-mac-boot/README.md, bin/omarchy-mac-kernel, mac-manual/content)
- https://github.com/omacom/omarchy-mac-installer (docs/image-producer.md, image-builder/README.md, scripts/supported-models.json, Engine/installer_data.json)
- https://github.com/omacom/omarchy-pkgs (pkgbuilds/linux-aurora, m1n1-aurora, uboot-asahi, omarchy-mac-boot, linux-aarch64-pkgbase-shim)
- https://pkgs.omarchy.org/edge/aarch64/omarchy.db (2026-10-14)
- https://github.com/asahi-alarm (PKGBUILDs, asahi-scripts, asahi-alarm-builder, asahi-installer-data)
- https://github.com/GravityLinux (installer, kiwi-descriptions, scripts, packages, u-boot, bootloader); https://cdn.gravitylinux.org/installer/installer_data.json
- https://asahilinux.org/docs/alt/boot-process-guide/
- https://archlinuxarm.org/packages/aarch64/{hyprland,quickshell,uwsm,sddm,chromium}
