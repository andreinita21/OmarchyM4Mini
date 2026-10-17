<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Installing Omarchy on the mini in place of Gravity Linux (no USB drive)

Phase 3 §5a ([plan](j773g-phase3-plan.md)) done directly: the Gravity Linux
installer already created the stub, firmware, EFI, Boot and Root partitions
on the mini (2026-10-17). Omarchy takes over those partitions; macOS, the
stub and the partition table are not touched. Gravity is gone afterwards
(reinstall from gravitylinux.org if ever wanted). Rung `u0` (USB SSD) is
skipped; its job, running the userland on real hardware before anything is
written, is replaced by two RAM boots of our kernel.

Three parts, one script each side:

| Part | Where | Command | Writes |
| --- | --- | --- | --- |
| 1 serve | host with `build/j773g` (the MacBook) | `tools/j773g-install.sh serve` | nothing; HTTP on port 8000 (also serves `boot.bin.omarchy` and `esp-fix-macos.sh`) |
| 2 prepare | the mini, in Gravity | `curl -fO http://HOST:8000/j773g-install.sh && sudo bash j773g-install.sh prepare http://HOST:8000` | ESP and Boot partitions |
| 3 root | the mini, RAM shell (`tools/j773g-boot.sh g6-display`) | `wget -O /tmp/install-root.sh http://HOST:8000/install-root.sh && sh /tmp/install-root.sh http://HOST:8000` | Root partition, then `m1n1/boot.bin` |

## What each part does

**serve** stages `build/j773g/install/` (`root.img`, `boot.img`, `esp.tar`
from the image's ESP files, the proxy `m1n1.bin` with the dockchannel fix,
the two scripts, a `MANIFEST` with sha256 and sizes) and runs Python's
`http.server`. It prints the host's addresses and the exact commands for
parts 2 and 3, including the busybox one-liner that brings `eth0` up with
DHCP in the RAM shell.

**prepare** finds Gravity's partitions from the mount table (`/`, `/boot`,
`/boot/efi`), insists they are on the internal NVMe, and cross-checks the
ESP against the stage-1 property `chosen/gravity,efi-system-partition`.
After typing `replace gravity` it:

0. asks whether Omarchy should encrypt the Linux root at its first boot
   (default **no**; `J773G_ENCRYPT=0|1` answers without the prompt). The
   answer goes to the ESP as `omarchy/install.conf` (`format=1`,
   `encrypt=0|1`) and into `omarchy/j773g-install.env` as `ENCRYPT=`.
   Omarchy's first boot treats a *missing* `install.conf` as "encrypt", and
   its owner setup then refuses an unencrypted root with "This Mac was set up
   to encrypt its disk, but the disk was not encrypted" (seen 2026-10-17).
   With "yes", a throwaway key is staged at `omarchy/luks-key` on Boot for
   the first boot's `omarchy-mac-encrypt` conversion; that path has not been
   exercised on the J773g yet,
1. backs up the whole ESP to `/var/tmp/j773g-install/esp-backup.tgz`
   (Gravity's root; copy it elsewhere if you want to keep it),
2. sets the ESP volume id to `4F4D-5801` (`fatlabel -i`; falls back to
   `mkfs.fat -i` + restore), which `omarchy-mac-boot` and the vendor-firmware
   initcpio hook hardcode,
3. unpacks our Limine, UKI and `limine.conf` onto the ESP, keeps Gravity's
   `vendorfw/` (Apple firmware), keeps Gravity's stage 2 as
   `m1n1/boot.bin.gravity`, stores the Omarchy stage 2 as
   `m1n1/boot.bin.omarchy`, and installs plain m1n1 as `m1n1/boot.bin` (and
   `boot.bin.proxy`) so the next boot is **proxy mode**,
4. reformats Boot as ext4 with Omarchy's UUID and fills it from `boot.img`
   (if Gravity has no separate `/boot`, part 3 disables the `/boot` fstab
   line instead),
5. writes `omarchy/j773g-install.env` on the ESP: Gravity's root partition,
   its filesystem UUID and size, `root.img`'s size and sha256.

Gravity keeps running until you power off, but cannot boot again.

**Between 2 and 3**, with the host on the mini's back-middle USB-C port:
`tools/j773g-adt-dump.sh`, `tools/j773g-boot.sh stock`, then
`tools/j773g-boot.sh g6-display`. The HDMI screen stays black while m1n1
waits in proxy mode: iBoot hands the stub a dummy framebuffer on this unit
and m1n1 is built with `NO_DISPLAY=1` (as Gravity builds it; its own DCP
bring-up crashes the T8132 display coprocessor). The kernel lights HDMI,
through `apple-dcp` and the DisplayPort PHY (`CONFIG_PHY_APPLE_DPTX`). A
black screen after the kernel starts is a kernel problem and must be solved
before part 3: boot with the network-reporting initramfs
(`BOOT_INITRD=build/j773g/initramfs-net.cpio.gz`, `j773g_host=HOST` in
`BOOT_ARGS`, a `nc -l 9999` loop on the host) to read the log without a
screen, then fall back through g5..g0 if needed. The `stock` rung (Gravity's
DT) needs `fw_devlink=permissive` with our config, because its dpaudio node
has no driver in the ladder kernel.

If the ESP already carries an older stage 2 (one that crashes the DCP, seen
as "AFK: ring buffer size mismatch" in the proxy log), boot the mini into
macOS from the startup picker and run, with serve still up on the host:
`curl -fO http://HOST:8000/esp-fix-macos.sh && sudo bash esp-fix-macos.sh
http://HOST:8000`. It replaces `m1n1/boot.bin`, `boot.bin.proxy` and
`boot.bin.omarchy` with the served builds (old files kept as `*.dcpcrash`).

**install-root.sh** (busybox) mounts the ESP by volume id, reads the env,
and refuses unless the recorded partition is on `nvme0n1`, still carries
Gravity's root filesystem UUID, is unmounted and large enough, and its name
is typed back. Then `wget | dd` streams `root.img` onto it, the written
bytes are hashed and compared with the host's live `MANIFEST` (not with what
`prepare` recorded, so the image may be rebuilt between parts 2 and 3), the
new btrfs UUID is checked, Boot is rewritten from `boot.img` and verified,
the ESP's `EFI/`, `limine.conf` and `boot.bin.omarchy` are refreshed from
`esp.tar` (vendorfw, `omarchy/`, `boot.bin.gravity` and `boot.bin.proxy`
stay), `omarchy/install.conf` is written from the recorded `ENCRYPT`
(default off; with it on, the throwaway key is staged on Boot), and only
then `boot.bin.omarchy` becomes `m1n1/boot.bin`. Root grows to the partition
on first boot (`x-systemd.growfs` in fstab).

The image's kernel command line carries `nosmp idle=nop`
(`J773G_CMDLINE` at image build, written into `KERNEL_CMDLINE[default]` of
`/etc/default/limine` before the UKI is built): without them the J773g boots
black and resets in a loop until iBoot shows "The version of macOS on the
selected disk needs to be reinstalled" for the stub (pick the Linux volume
in the startup picker to boot it again).

**Re-installing** (for example after an interrupted part 3): boot the g6
shell again, run part 3 again. It rewrites root, Boot and the ESP's boot
files from the served image and resets Omarchy's first-boot state with
them. To get back to proxy mode first, `esp-fix-macos.sh` from macOS puts
the plain m1n1 back as `boot.bin`; `esp-switch.sh` (RAM shell, one line:
`cd /tmp && wget http://HOST:8000/esp-switch.sh && sh esp-switch.sh
http://HOST:8000`) only refreshes the ESP and switches without touching
root. Both are served next to `install-root.sh`.

## Afterwards

Power-cycle: m1n1 → U-Boot → Limine → UKI → Omarchy first boot and owner
setup on HDMI (USB keyboard on a rear port). Then plan P3.6
(`omarchy-apple-silicon-boot-check`, `omarchy update`, shutdown test).

Going back:

- proxy mode again: copy `m1n1/boot.bin.proxy` over `m1n1/boot.bin` on the
  ESP (from Omarchy, or from macOS after `diskutil mount` of the EFI slice),
- Gravity's stage 2: `m1n1/boot.bin.gravity`; its root is gone after part 3,
- macOS: boot picker (hold the power button), untouched throughout.

## Known limits

- GPU is llvmpipe until rung `g8-gpu` passes and a Mesa package exists;
  audio is off (speaker safety review pending); Wi-Fi uses Gravity's
  `vendorfw/` NVRAM (V=u on a V=a unit, see P3.7). Ethernet first.
- The transfer needs the mini and the host on the same wired LAN. Without
  one, `root.img` can be written from macOS on the mini with this SSD
  plugged in (`sudo dd if=root.img of=/dev/rdisk0sN bs=4m`), after parts 1
  and 2; the switch of `boot.bin` then happens by hand.
