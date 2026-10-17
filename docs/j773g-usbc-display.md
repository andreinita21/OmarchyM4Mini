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
