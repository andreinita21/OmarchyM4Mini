<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# J773g USB-C DisplayPort — work in progress (not in any package)

Against GravityLinux/linux `gravity-m4` @ `4fc326f6c25ccceb7515e2635c22e01fde5d3bac`
(7.1.13). Target: the Samsung Odyssey G8 OLED on the **back-right** USB-C port
(usb-pd@8, atcphy3 @ 0x41b000000, typec/port2), driven by the spare display
coprocessor dcpext0 (dcp@286e00000). Research and the plug test:
[docs/j773g-usbc-display.md](../../docs/j773g-usbc-display.md).

| File | What |
| --- | --- |
| `0001-tipd-hpd.patch` | Port of Asahi fairydust 296c91ac1fa5 (Janne Grunau): tipd keeps data_status changes for CD321x/SN201202X |
| `0002-tipd-dp-hpd-oob-hotplug.patch` | Port of fairydust 9c16792154f8 (Janne Grunau) plus glue: HPD from the Type-C controller goes to the DCP named by the connector's `displayport` phandle (`drm_connector_oob_hotplug_event()`); logs DP mode, pin assignment, HPD |
| `0003-apple-dcp-usbc-link.patch` | apple-drm: for DP/USB-C connectors the DPTX link follows HPD instead of connecting at startup; every DPTX firmware call logged; `appledrm.dptx_usbc_phy_dryrun` (default on) answers PHY calls without touching the ATC PHY. HDMI unchanged |
| `0010-atc-t8122-dp-experimental.patch` | phy-apple-atc: `t8122_dp_experimental` (default off) runs the T8103-generation DP aux power-up and lane-config tail on T8122/T8132; logs each DP step |
| `t8132-j773g-usbc-dp.dtsi` | dcpext0 → atcphy3 (`phys`, `apple,connector-type = "DP"`, `apple,dptx-phy = <3>`), typec3 `displayport = <&dcpext0>`, and the atc3 display crossbar (`apple,t8132-display-crossbar`, fallback `t6020`, 0x4_1b04c000) with `mux-index = <1>` |
| `test-kernel.fragment` | Config on top of the package's for RAM test boots: USB-C, PHY, crossbar, tg3, xHCI/dwc3 built in, Rust off |

## Results on the mini (2026-10-18, RAM boots through the proxy, watchdog armed)

Test kernel = package config + `test-kernel.fragment` + these patches, busybox
netlog initramfs, `tools/j773g/watchdog_boot.py` (one 120 s hardware watchdog;
the built-in apple_wdt adopts it, so a hung kernel resets into the proxy — it
did once, after a bad `devmem` read).

Working end to end:

    apple-display-crossbar 41b04c000.mux: Switched dpphy to dispext0,1
    apple-dcp 286e00000.dcp: DCP index:1 dptx target phy: 3 dptx die: 0
    sn201202x 0-08: DP alt-mode: on, pin assignment E, HPD high (data status 0x80008113)
    apple-dcp 286e00000.dcp: USB-C DP: HPD high, connecting DPTX port 0 to atc 3 die 0
    apple-dcp 286e00000.dcp: USB-C DP: DPTX port 0 fw call group 0 #0 activate
    apple-dcp 286e00000.dcp: USB-C DP: get_max_lane_count: ... ATC reports 4 lanes, answering 4

- The t6020 crossbar layout and input 1 for dcpext0 are right on T8132
  (ADT `display-crossbar0`: dcp 0, dcpext0 1, dcpext1 2;
  `atc3-dpphy dp-switch-dfp-endpoint = 3` matches `apple,dptx-phy = <3>`).
- Unbind/bind of the SN201202X driver (`/sys/bus/spmi/drivers/sn201202x`,
  device `0-08`) replays HPD: a software replug for live experiments.
- `USB_DWC3` must be built in for the test kernel: tipd defers until dwc3's
  role switch exists.

Not working: the DCP firmware's AUX transactions get no answer
(`device_not_responding` every 0.5 s, then `inactive_sink_detected`), with
and without `phy_apple_atc.t8122_dp_experimental=1` and dry-run off.

- On T8132 the T8103-generation lpdptx AUX_CFG_BLK writes do not stick:
  `lpdptx+0x08` stays 0xFFFF0000, `+0x0c` 0x7, `+0x204/+0x208` 0, the
  RXOFFSET field of `+0x0` stays 0. Only `lpdptx+0x4000` (AUX_CONTROL: sleep,
  clamp, power-down, TXTERM) responds (0x14 idle → 0x43 after the sequence).
- m1n1 applies the ADT `tunable_AUX_TOP` at core+0x16000 on the active port:
  +0x16008 = 0x8, +0x1600c = 0x48E0 (idle port: all zero). Most of that block
  ignores writes (only +0x0c took one); it is not where the old AUX_CFG_BLK
  values belong.
- The HDMI dptx-phy (0x39a740000, Gravity's working T8122 activation) has a
  much richer +0x4000 block (calibration at +0x4200..+0x4228); the ATC lpdptx
  is a different, smaller design.

Next step: trace macOS driving the G8 on atcphy3 under the m1n1 hypervisor
(upstream m1n1 main has M4/SPTM support since 2026-10-16) — the writes to
atcphy3 core, lpdptx and atc3-dpxbar give the T8132 DP sequence.
