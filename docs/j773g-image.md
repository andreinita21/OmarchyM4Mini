<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# The J773g Omarchy image (Phase 3, P3.1–P3.2)

Status 2026-10-14: **build tooling written; nothing booted.** Plan and
decisions: [j773g-phase3-plan.md](j773g-phase3-plan.md).

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

## Not done yet

- First run of `tools/j773g-image.sh` (needs the kernel package built and
  ~4 GB of downloads).
- QEMU smoke test of `root.img` with the J773g kernel (`Image` from the
  package, generic virt machine): systemd to `multi-user.target`,
  `omarchy-hw-platform` → `aarch64-apple` from the manifest.
- Rung `u0` and everything on hardware (plan §5–§6).
