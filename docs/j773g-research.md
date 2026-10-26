<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# J773g research notes (2026-10-13)

Answers to the open questions in [PLAN.md](../PLAN.md) section 7, from public
sources plus this mini's own macOS IORegistry. "Confirmed" means a primary
source says so; nothing here has been tested on this unit yet.

## 0. Prior art: Gravity Linux targets exactly this machine

[Gravity Linux](https://github.com/GravityLinux) is a Fedora remix whose
[installer](https://github.com/GravityLinux/installer) supports **only** the
M4 Mac mini (`t8132`, `j773gap`). Its pieces:

| Repo | What | Relevance |
| --- | --- | --- |
| `GravityLinux/linux`, branch `gravity-m4` | Kernel with a full `t8132-j773g.dts`: DCP/HDMI, GPU, NVMe, USB (all four ATCs, front hub), Ethernet, Wi-Fi/BT board type, speaker | Hardware-tested on M4 minis (commit messages: Fedora boot, appledrm handoff at 4.2 s, USB-PD on SPMI SID 8) |
| `GravityLinux/bootloader` | m1n1 fork: T8132 NVMe, DCP firmware-compat for macOS 26.6.2, ATC PHY tunables, CTRR reservation, GPU platform data | The stage 1/2 their installer ships |
| `GravityLinux/installer` | Asahi-installer derivative, J773g only, macOS ≥ 26.5, stub from the 26.6.2 IPSW | Reference for the stub install (PLAN Phase 1 step 3) |
| `GravityLinux/adt-collection` | ADTs from various boards | Possible offline J773g ADT reference |

Consequences for this fork:

- Their J773g values were adopted where they are hardware-proven and agree
  with this mini's ioreg (commit "dts: j773g adopt hardware-tested values
  from GravityLinux's J773g tree"): framebuffer on `ps_dispext0_fe`, port 0
  pwren SMC GPIO 19, Ethernet bus 2, hub GPIO hogs, port labels.
- `tools/j773g-build.sh gravity` builds their tree (same config fragment,
  simpledrm console) as a **known-good control** for the first boot. If our
  r0 fails and Gravity's control boots, the fault is in our tree or
  patches, not the boot chain.
- `M1N1_FLAVOUR=gravity tools/j773g-build.sh m1n1` builds their m1n1.

## 1. DFU port, proxy port, serial port

- **DFU port = the middle rear USB-C port** (Apple support
  [120694](https://support.apple.com/120694); front ports do not do DFU).
  Confirmed.
- That port is **atc0** (Gravity labels `typec0` "USB-C Back-middle";
  `typec1` = back-left = atc1, `typec3` = back-right = atc3; the front ports
  sit behind the hub on atc2).
- m1n1's USB proxy gadget comes up on every `usb-drd`/`atc-phy` pair
  (`src/usb.c`, up to 8), so any rear port works; use the **back-middle**
  port by convention. Confirmed from m1n1 source.
- Serial debug (Central Scrutinizer / macvdmtool): Asahi's generic rule for
  minis is "the port closest to the power plug". Not verified for M4.

## 2. Front USB-C ports and the GL3590 hub

- This mini's ioreg shows `usb3hub-fw@0` (`compatible usb3hub-fw-gl3590,spi`)
  on spi3, with functions `usb3hub_rst` = gpio 198, `usb3hub_flash_oe` =
  gpio 101, `usb3hub_fwload_done` = gpio 102, `usb3hub_flash_wp` = gpio 193.
- Gravity drives 101 and 198 high with GPIO hogs and gets working front
  ports, i.e. the hub boots its own SPI NOR once released; no Linux firmware
  loader is needed. Adopted in the `USB_ATC23` layer.
- Gravity also sets `apple,fixed-usb3` / `apple,fixed-lane-swap` on atcphy2;
  those properties do not exist in the Asahi 77cb8f24c2 ATC driver, so the
  front ports may need Gravity's PHY driver changes as well.
- No GL3590 entry in Linux's `onboard_usb_dev` driver. Not needed.

## 3. PCIe port power

- Asahi's minis (j274, j473, j474s): Wi-Fi port 0 pwren = SMC GPIO 13;
  Ethernet port 2 has no pwren on any of them. Confirmed (dts).
- Gravity's T8132 `t8132-jxxx.dtsi`: port 0 supply = SMC GPIO **19**
  (regulator `pwren-pcie0-port0`). Adopted as `pwren-gpios` (our kernel's
  pcie-apple reads `pwren-gpios`, not a regulator). INHERITED: our ioreg
  bridges carry no pwren property.

## 4. Wi-Fi / Bluetooth

- **BCM4388 rev C2**, module `sakhalin`, PCI 14e4:4434 (the macOS
  compatible string says `bcm4387`, misleadingly). Firmware dir in macOS:
  `C-4388__s-C2/`. Confirmed by Gravity's installer tests.
- Upstream asahi-fwextract skips `C-4388__s-C2` ("broken firmware dir in
  14.6.1 IPSW"), so Asahi's extraction drops this mini's Wi-Fi firmware;
  Gravity's `gravity-fwextract` handles it. Mainline brcmfmac lacks 4388;
  Asahi adds it. Gravity's `gravity-m4` brcmfmac already has the BSS-info
  v116 change and maps rev >= 4 (C2 included) to the `brcmfmac4388c0-pcie`
  firmware names that its fwextract writes, so upstream's
  `brcmfmac-bcm4388-rev6-c2-v116.patch` is not needed on the Gravity base
  (checked 2026-10-14).
- Bluetooth needs per-unit beamforming calibration (`BTBF` from
  `BWCl-sakhalin-4388-C2-*` records); Gravity passes it via U-Boot.
- Out of scope for the first weekend.

## 5. m1n1 on M4

- AsahiLinux/m1n1 v2.0.0 (2026-09-30) and later carry T8132 support: SMP,
  PCIe, NVMe, MCC, CTRR reservation, a J773g ATC tunable alias. Build here:
  v2.0.0-27-g94395adc.
- Hypervisor on M4: fixes are landing as of 2026-09-25 … 2026-10-13
  (SPTM sysreg emulation, "Fix M4* boot under hypervisor", 24 MHz timer
  emulation). Status: likely partially working, unannounced. Upstream
  Omarchy found it crashing in August; retry it as a debugging tool, but
  don't depend on it.
- Sven Peter sent an M4/A18 Pro DT pull request for Linux 7.4
  (2026-10-02). Asahi's M4 feature page still lists every subsystem as TBA.

## 6. SMC shutdown

On the Air, `macsmc-reboot` had no NVMEM cells, so
shutdown wrote `MBSE=off1` without the stay-off flag and the machine
restarted. The fix was DT-only (four NVMEM cells, PMU at `0xf800`).
Likely the same on the mini; check when the SMC layer gets a poweroff test.

## 7. Installing the m1n1 stub on M4

- The Asahi installer does **not** support M4 (chip table ends at M3).
- Gravity's installer does, for J773g only. It requires macOS ≥ 26.5 on the
  main system and installs the stub from the qualified **26.6.2** IPSW
  (recovery image decoded with `/usr/bin/aea`). It also applies the macOS 27
  boot-picker fix (`fsctl_set_bootable` on the stub volume).
- Manual route (Asahi m1n1 user guide): in the stub's 1TR,
  `kmutil configure-boot -c m1n1.bin --raw --entry-point 2048
  --lowest-virtual-address 0 -v <stub volume>`, with the stub set to
  Permissive Security. Upstream Omarchy did this on the Air's own macOS
  volume, which leaves macOS unbootable until `bputil -f` from 1TR. That
  conflicts with this project's "macOS stays bootable" rule, so it is not
  the recommended path here.
- The mini runs macOS 27.0.1 (iBoot 20457.1.29). The stub's macOS version,
  not the main one, sets the firmware Linux sees; Gravity's m1n1 has DCP
  compatibility code for 26.6.2.

## Sources

- https://support.apple.com/120694
- https://asahilinux.org/docs/hw/soc/serial-debug/
- https://asahilinux.org/docs/sw/m1n1-user-guide/
- https://asahilinux.org/docs/platform/feature-support/m4/
- https://github.com/AsahiLinux/m1n1 (src/usb.c, git log)
- https://github.com/AsahiLinux/linux/tree/asahi/arch/arm64/boot/dts/apple
- https://github.com/AsahiLinux/asahi-installer/blob/main/asahi_firmware/wifi.py
- https://github.com/GravityLinux/installer, /linux (gravity-m4), /bootloader

- https://lore.kernel.org/lkml/20261002190232.6449-1-sven@kernel.org/
