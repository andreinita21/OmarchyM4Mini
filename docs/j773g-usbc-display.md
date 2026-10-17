<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# J773g USB-C / Thunderbolt video out — research (2026-10-17)

Goal: native DisplayPort alt-mode on the back USB-C ports (not DisplayLink).
Target monitor: Samsung Odyssey G8 OLED 34" over a USB-C to DisplayPort 1.4
cable, 3440x1440 at up to 175 Hz like macOS — 4-lane HBR3 DP alt-mode.
Status: **not working**. Read-only research only so far.

## Port map (live, kernel 7.1.13-1-7)

| USB-PD | ATC PHY | Port | sysfs |
| --- | --- | --- | --- |
| usb-pd@c | atcphy0 0x403000000 | back middle (DFU) | typec/port0 |
| usb-pd@a | atcphy1 0x40b000000 | back left | typec/port1 |
| usb-pd@8 | atcphy3 0x41b000000 | back right | typec/port2 |
| — | atcphy2 0x413000000 | front (GL3590 hub, `apple,fixed-usb3`) | — |

macOS's ADT lists a display crossbar with outputs atc0..3, lpdptx and dptx,
so any free DCP should be routable to any back port (inference).

## What works already

- `dcp@286e00000` and `dcp@48ae00000` (`apple,t8132-dcpext`) boot with this
  mini's 26.6.2 firmware under Gravity's apple-drm ("DCP booted",
  `dcp_hotplug() connected:0`). DRM shows them as `Unknown-2/3`
  (no `phys`, no connector type in the DT).
- The SN201202X USB-PD controllers advertise DisplayPort (`ff01`, vdo 0xc02)
  and Thunderbolt (`8087`) on every back port; tipd's own DP-mode entry
  already calls the Type-C mux (`tipd/core.c:554-593`).
- apple-drm takes connector type `DP` / `USB-C` from the DT
  (`dcp.c:1739-1746`) and has the oob hotplug hook (`apple_drv.c:329-343`).
- Config needs no change for a first attempt (DRM_APPLE=y, PHY_APPLE_DPTX=y,
  PHY_APPLE_ATC=m, TYPEC_SN201202X=m, TYPEC_DP_ALTMODE=m, MUX_APPLE_DPXBAR=m).

## What is missing

1. tipd: forward HPD to the DCP (Asahi `fairydust` 296c91ac1fa5 and
   9c16792154f8, M1/M2). Small.
2. DT for one port, e.g. dcpext0 -> atcphy1 (back left): `phys = <&atcphy1
   PHY_TYPE_DP>`, `phy-names = "dp-phy"`, `apple,connector-type = "DP"`,
   `displayport = <&dcpext0>` on the Type-C port (as fairydust bd435201b527).
   The dptx-phy index and die value are guesses. Small.
3. apple-drm: on 26.6.2 it connects the link at startup (`dcp.c:1178`),
   right for HDMI, wrong for USB-C; gate it on HPD. Small.
4. **Main blocker:** phy-apple-atc has the DP framework but on T8122/T8132
   the DP lane tunables are dropped (`atc.c:2387-2390`), DP aux enable is a
   FIXME (`atc.c:1350-1352`, `1404-1406`) and the lane-config tail is skipped
   (`atc.c:1318-1320`); m1n1 copies no `tunable_*DP*` for T8122
   (`kboot_atc.c:100-125`). Same in Asahi `fairydust`. Needs reverse
   engineering (m1n1 hypervisor trace of macOS plugging a DP monitor).
5. Display crossbar: `apple-display-crossbar.c` matches t8103/t8112/
   t6000/t6020 only; no T8132 node (`atcN-dpxbar` at 0x4_0304c000,
   0x4_0b04c000, 0x4_1b04c000). Needs reverse engineering.

Items 1-3: days. Items 4-5: new driver work, weeks to months; nobody
(Asahi included) has DP programming for the T8122-generation ATC PHY.

## Bandwidth note for the target

3440x1440 at 175 Hz needs about 21-23 Gbit/s: 4-lane HBR3 (25.92 Gbit/s
payload) with no USB3 lanes kept (pin assignment C/E). Two lanes or a lower
link rate would mean a lower refresh. Whether the DCP firmware path offers
175 Hz on Linux is unknown until a picture comes up.

## First experiment (no code change)

Monitor on back left (port1) with a plain USB-C to DP cable, keyboard on
another port: capture dmesg, `/sys/class/typec/port1*`, the tps6598x trace
events — does the controller enter DP mode, which pin assignment, does HPD
toggle. Putting a port in DP mode drops its USB3.

## Plug test result (2026-10-17 23:57, kernel 7.1.13-1-7)

Odyssey G8 OLED 34" on the **back right** port (usb-pd@8, atcphy3,
typec/port2) with a plain USB-C to DP 1.4 cable. tps6598x trace events
(`/sys/kernel/tracing/events/tps6598x`):

    cd321x_data_status: DATA_CONNECTION|DATA_UPSIDE_DOWN|USB2_CONNECTION|DP_CONNECTION|0x80000000, DP pinout E
    cd321x_data_status: DATA_CONNECTION|DATA_UPSIDE_DOWN|USB2_CONNECTION|DP_CONNECTION|HPD_LEVEL|0x80000000, DP pinout E

The controller enters DP alt-mode on its own, picks **pin assignment E (all
four lanes to DP)** — what 3440x1440 at 175 Hz needs — and the monitor raises
HPD. Cable orientation: upside down. Partner identity: id_header 0xc3249b00.
Nothing else reacts: no ATC PHY, crossbar or DCP messages; `card1-Unknown-2/3`
stay disconnected. Back left (port1) was busy with the keyboard receiver,
back middle (port0) with the proxy cable.

## Night of 2026-10-17/18: what works, what blocks

RAM boots of a test kernel through the proxy (watchdog-protected,
[patches-kernel/j773g-usbc-dp/](../patches-kernel/j773g-usbc-dp/)) take the
G8 on the back-right port as far as: crossbar switched to dcpext0 (t6020
layout, input 1), SN201202X DP pin assignment E + HPD forwarded, DCP
connects DPTX port 0, PHY activate, 4 lanes. The DCP's AUX transactions get
no answer: the T8132 ATC lpdptx AUX configuration is not the T8103
generation's (register readings in the patches README). No Asahi branch has
T8122/T8132 DP AUX code (fairydust has the same FIXMEs; sven/atcphy,
atcphy/2025-experiments and dp-altmode-WIP predate T8122).

**Next: trace macOS** driving the G8 under the m1n1 hypervisor.
- Upstream m1n1 main (5531393a, M4/SPTM hypervisor support since
  2026-10-16) builds for the mini with `NO_DISPLAY=1`; it needs kb2uka's
  `dockchannel-tx-bound.patch` (upstream still spins on DATA_TX_FREE, issue
  #82). Built: `build/j773g/hv/m1n1.{bin,macho}` (git-ignored). The first
  chainload attempt, without that patch, hung the mini.
- Tracer: [tools/j773g/hv/trace_j773g_dp.py](../tools/j773g/hv/trace_j773g_dp.py)
  (atc-phy3 + atc3-dpxbar, SYNC).
- Booting macOS as a guest needs a macOS whose boot policy is "permissive"
  with m1n1 as custom kernel (`kmutil configure-boot` in recoveryOS), plus its
  kernelcache, SPTM and TXM images from Preboot. Either the main macOS
  (reversible) or a second macOS volume used only for tracing. Owner's
  decision.
- Morning recovery: the mini is stuck in the chainloaded m1n1; power-cycle,
  hold the power button for the startup options, pick macOS; from macOS the
  ESP's `m1n1/boot.bin` goes back to the Omarchy stage 2, then
  `update-m1n1` in Omarchy refreshes it with the current DTB.
