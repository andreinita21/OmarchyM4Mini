<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# J773g home-day checklist

Exact steps for the first hardware session on the M4 Mac mini. Everything
before section 3 was prepared offline on 2026-10-13. **Every step marked
APPROVAL changes the mini's disk or boot policy. Andrei decides; nothing
runs on its own.**

Background: [PLAN.md](../PLAN.md), [research notes](j773g-research.md),
running log [NOTES.md](../NOTES.md).

## 0. Before anything: recovery path (read once)

- **1TR / recoveryOS:** shut down, then press and hold the power button until
  "Loading startup options" appears. The boot picker lists macOS and any
  stub. Pick macOS to get back to normal at any time.
- **DFU revive** (if the boot chain itself breaks): another Mac with Apple
  Configurator, a USB-C cable into the mini's **back-middle** port (the DFU
  port), then hold power while connecting. Use **Revive**, never **Restore**
  (Restore wipes the disk).
- Time Machine or other backup of anything on the mini that matters.

## 1. Pick the host

Once the mini boots m1n1, macOS is not running, so another machine drives
the loop over USB-C. Any Mac or Linux box with Python 3 and a USB-C port.

```sh
git clone https://github.com/andreinita21/OmarchyM4Mini.git
cd OmarchyM4Mini && git switch j773g
python3 -m pip install --user pyserial==3.5 construct==2.10.70
```

Copy the boot kit built on the mini (it is git-ignored, ~45 MB):

```sh
# on the mini, before shutting it down:
cd ~/OmarchyM4Mini && tar czf ~/j773g-kit.tgz build/j773g/{Image.gz,initramfs.cpio.gz,dtb,m1n1,m1n1-gravity,gravity}
# copy ~/j773g-kit.tgz to the host (AirDrop / scp), then on the host:
cd OmarchyM4Mini && tar xzf ~/j773g-kit.tgz
```

Or rebuild it on the host if it is arm64 with Docker: `tools/j773g-build.sh all && tools/j773g-build.sh gravity`.

## 2. Get m1n1 onto the mini — APPROVAL

The mini needs a stub (a small extra macOS boot volume set to Permissive
Security) whose boot object is m1n1. macOS stays on its own volume, untouched
and bootable from the boot picker.

The Asahi installer does not support M4 yet. Options:

| | Route | Disk changes | Notes |
| --- | --- | --- | --- |
| **A (recommended)** | Gravity Linux installer (`curl -fsSL https://install.gravitylinux.org \| sh` from macOS) | Shrinks macOS (installer's resize step), adds stub + EFI + Boot + Root partitions | Only J773g-supported installer. Installs Gravity Linux 44 KDE developer alpha, stub on macOS 26.6.2 firmware. Requires main macOS ≥ 26.6.2 (we have 27.0.1). Gives a known-good Linux to compare against. Has the macOS 27 boot-picker fix (`f` option) if the stub doesn't show up |
| B | Manual stub (Asahi m1n1 user guide) | Same shrink + a hand-made stub | No M4 tooling; high effort |
| C | Upstream Omarchy's Air method: `kmutil configure-boot` on the **main** macOS volume | None to partitions, but macOS stops booting until `bputil -f` | Breaks the "macOS stays bootable" rule. Not recommended |

Route A, step by step (on the mini, in macOS, with time to spare):

1. Free space: the installer asks how much to give Linux. 60–80 GB is
   enough (the internal disk has ~96 GB free today).
2. Run the installer command above and follow its prompts. It will ask for
   the admin password, show the resize, then tell you to shut down and
   finish in 1TR (hold power → pick the new stub → follow the steps it
   prints, which include setting Permissive Security for the stub only).
3. Boot the stub once and check that Gravity Linux reaches its desktop on
   HDMI. That proves m1n1 + firmware + DT on this unit. Note anything odd in
   NOTES.md.

## 3. Put the mini into m1n1 proxy mode — APPROVAL (writes the EFI partition)

The installer's m1n1 stage 1 chainloads `m1n1/boot.bin` from the EFI
partition (stage 2 = m1n1 + U-Boot + DTBs). A plain m1n1 with no payload as
stage 2 waits in **proxy mode** on USB, which is what the loop needs.

From Gravity Linux on the mini (or from macOS with the ESP mounted):

```sh
# Gravity Linux: ESP is usually /boot/efi
sudo cp /boot/efi/m1n1/boot.bin /boot/efi/m1n1/boot.bin.gravity   # keep the original
sudo cp m1n1.bin /boot/efi/m1n1/boot.bin    # build/j773g/m1n1-gravity/m1n1.bin (or m1n1/ for Asahi's)
```

Undo (back to booting Gravity): `sudo cp /boot/efi/m1n1/boot.bin.gravity /boot/efi/m1n1/boot.bin`.
If the ESP is unreachable from Linux, mount it from macOS with
`diskutil list` → `sudo diskutil mount diskXsY` (the "EFI - GRAVI…" partition).

Then power the mini on with the host connected by USB-C cable to the mini's
**back-middle** port. The HDMI screen shows the m1n1 logo and stays there.

## 4. On the host: find the proxy device and dump the ADT

```sh
ls /dev/ttyACM* 2>/dev/null; ls /dev/cu.usbmodem* 2>/dev/null
export M1N1DEVICE=/dev/ttyACM0          # Linux; macOS: /dev/cu.usbmodemXXXX01 (first of the two)
tools/j773g-adt-dump.sh                 # -> private/adt-live-<timestamp>/ (never commit)
```

Then power-cycle the mini (hold power ~10 s, press again) to return to the
proxy prompt for the next step. Phase 1 step 7 (Fable, high) diffs this ADT
against PLAN.md.

## 5. The boot ladder (RAM only)

One rung per boot, power-cycle the mini back into proxy mode between rungs.
Plug a USB keyboard into a **back-left or back-right** port before r3
(the back-middle port carries the host cable).

```sh
# known-good control first: Gravity's kernel + DT, simpledrm console
BOOT_KIT=$PWD/build/j773g tools/boot.sh build/j773g/gravity/t8132-j773g.dtb gravity-control build/j773g/gravity/Image.gz

tools/j773g-boot.sh r0-boot      # expect: penguin, "=== J773g initramfs", a shell prompt
tools/j773g-boot.sh r1-smc       # + macsmc probe lines
tools/j773g-boot.sh r2-storage   # + nvme0n1 in /proc/partitions (read-only; nothing mounts it)
tools/j773g-boot.sh r3-usb       # keyboard types in the shell
tools/j773g-boot.sh r4-pcie      # `ip link` shows eth0 (tg3)
tools/j773g-boot.sh r5-atc23     # keyboard on a front port works
```

After each attempt append an entry to NOTES.md (format in START_HERE.md
section 6): rung, what the screen showed (a phone photo of the last lines is
ideal), and the boot log path printed by the script.

If a rung is black:

1. Boot the Gravity control. If that is also black → boot chain / m1n1 /
   firmware problem, not our DT. Try the other m1n1 flavour.
2. If the control works and r0 does not → compare r0 with the control's DT
   (framebuffer node, power domains). Our kernel is Asahi 77cb8f24c2 +
   upstream M4 hacks; Gravity's kernel is newer.
3. The m1n1 hypervisor is gaining M4 support upstream (2026-09/10); if it
   works now, `run_guest.py` gives a console over USB. Try it only after
   1 and 2.

## 6. Afterwards

- Back to macOS: hold power → pick Macintosh HD. macOS is untouched.
- Restore Gravity's stage 2 (section 3 undo) if you want the stub to boot
  Gravity again.
- Commit NOTES.md and any DT fixes; raw logs and ADT dumps stay in private/.
