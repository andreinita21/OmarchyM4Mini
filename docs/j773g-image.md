<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# The J773g Omarchy image (Phase 3, P3.1–P3.2)

Status 2026-10-14: **packages and image build; the image boots in QEMU to the
login prompt.** Nothing has run on the mini. Plan and decisions:
[j773g-phase3-plan.md](j773g-phase3-plan.md).

## Pieces

| Path | What |
|---|---|
| `packaging/j773g/*/PKGBUILD` | The four J773g packages ([README](../packaging/j773g/README.md)) |
| `tools/j773g/Dockerfile.alarm`, `tools/j773g-pkg.sh` | Arch Linux ARM build container and `makepkg` wrapper. `tools/j773g-pkg.sh image`, then `tools/j773g-pkg.sh all` → `build/j773g/pkgs/` |
| `tools/j773g-image.sh`, `tools/j773g/image-build.sh` | The image builder (privileged container: loop devices + btrfs). Output `build/j773g/image/`: `root.img`, `boot.img`, `esp/`, `installer_data.json`, `packages.txt`, `logs/` |
| `tools/j773g/finalize-root`, `tools/j773g/node.pin` | Copied unchanged (MIT) from omacom/omarchy-mac-installer `image-builder/builder/`: the image-only root edits (locale, keyboard, GRUB defaults, splash, SDDM, identity scrub) and the Node.js pin owner provisioning unpacks offline |

## What the builder does (mirrors `build-mac-image`)

1. Trusts the Asahi ALARM and Omarchy repository keys on the build host by
   installing their keyring packages and checking the fingerprints
   (`12CE6799…97FB8FEB`, `40DFB630…80CAC571`).
2. Build `pacman.conf`: a local unsigned `[j773g]` file repository with our
   packages, then Omarchy's Apple Silicon order: `[omarchy]` (edge),
   `[asahi-alarm]`, Arch Linux ARM through `arm-mirror.omarchy.org`.
3. Filesystems with fixed identities: btrfs root (`@ @home @log @pkg`, later a
   sealed read-only `@factory`), ext4 `/boot` (2 GiB), FAT ESP (500 MB).
4. Installs base + `omarchy-settings-dev` alone (platform guard), writes the
   image-target manifest (`platform=aarch64-apple`), then `omarchy-dev` with
   the base and aarch64 package lists (packages Arch Linux ARM lacks are
   recorded in `unavailable`), then the Apple list, the four J773g packages,
   `mkinitcpio limine limine-snapper-sync limine-mkinitcpio-hook asahi-scripts
   asahi-fwextract`, and `alsa-ucm-conf-asahi asahi-audio`.
5. `omarchy-apply-system --defer-provisioning --first-install` in an isolated
   chroot whose device tree says `apple,arm-platform` and whose UEFI has no
   variables. Finalizer, Mac presets, the runtime's `aarch64-apple` edge
   pacman template (plus `IgnorePkg` for the four local packages), owner
   provisioning staged with the pinned Node.js.
6. `mkinitcpio -P`, `LC_ALL=C update-m1n1` (stage 2 = m1n1-gravity +
   `t8132-j773g.dtb` + uboot-gravity, via omarchy-j773g's `DTBS` drop-in),
   Limine activation through `omarchy-lifecycle-dispatch setup-boot`, first
   boot armed, `@factory` sealed, root shrunk to content.

Differences from the official producer, on purpose: no signed candidate set
(local packages), `omarchy-dev` / `omarchy-settings-dev` as the runtime (the
`aarch64-apple` platform lives on Omarchy's master, published as `-dev` on
edge), `image_profile=lab`, no package provenance record, no first-boot
rehearsal probe.

## Findings from the first builds (2026-10-14)

- The four packages build in the ALARM container: m1n1-gravity 208 KB,
  uboot-gravity 254 KB (carries `apple,t8132` and the `gravity,efi-system-partition`
  lookup), linux-gravity-m4 30 MB + headers (about 9 min), omarchy-j773g.
- The image builds end to end in about 7 minutes once the package cache is
  warm: 893 packages, `root.img` 12.7 GB, a 62 MB UKI, stage 2 = m1n1 +
  exactly one device tree (t8132-j773g) + U-Boot.
- `omarchy-mac-boot` hardcodes Omarchy's disk identities (ESP volume id
  `4F4D-5801`, boot UUID `4f4d5801-424f-…`, root label `OMARCHY_ROOT`) in its
  initramfs hooks and provisioning; the image uses exactly those.
- Kernel config lessons (all in `j773g.fragment`): `DRM_APPLE` must be built
  in (modpost: non-exported arch helpers) which needs `TYPEC=y`; `BTRFS_FS=y`
  because the Mac boot hooks mount the root before udev autoloads modules;
  `SERIAL_AMBA_PL011` + built-in virtio so QEMU can show a console. The Asahi
  config has no generic PCI host bridge, so QEMU uses virtio-mmio devices.

## QEMU smoke boot (2026-10-14)

`tools/j773g-image-smoke.sh` lays `esp/`, `boot.img` and `root.img` into one
GPT disk (EFI 500 MB, Boot 2 GiB, Root), as the installer would, and boots the
packaged kernel with the image's own initramfs on a virt machine (TCG inside
the container, about 7 minutes to the prompt). Seen on the console:

- the vendor-firmware and encryption hooks find the ESP and the root partition;
  encryption correctly declines ("not a fresh image" without an installer
  `install.conf`), the root is mounted by UUID and systemd switches root;
- "Omarchy first boot" runs the deferred hardware steps ("Setting up your
  Mac's hardware...") and finishes; owner provisioning starts and waits for
  the wizard on tty1; `omarchy login:` appears;
- the only failure is speakersafetyd, which has no speaker hardware in QEMU
  (and no speaker driver in this kernel on purpose).

This proves the root, the kernel package, the initramfs hooks and the boot
identities. It proves nothing about m1n1, U-Boot, Limine or the Mac.

## Not done yet

- Rung `u0` (Omarchy root on a USB SSD, kernel from RAM) and everything on
  hardware (plan §5–§6). U-Boot → Limine on T8132 is the first unknown there.
- The kernel command line for the Mac (`J773G_CMDLINE`) once the ladder says
  what the mini needs.
