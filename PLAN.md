<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# PLAN — Linux bring-up on the base M4 Mac mini (Mac16,10 / J773g / T8132)

Status: **skeleton, 2026-10-13.** The real plan (shared / missing / new nodes,
ordered subsystem list) is produced in Phase 1 step 7 after the live ADT is
dumped through m1n1 proxy mode and diffed against upstream's J713 findings
(`docs/t8132-adt-audit.md`, `docs/t8132-gap-analysis.md`). Until then this
file only fixes the goal, the constraints and the order of work. Rules live in
`START_HERE.md`; the running log lives in `NOTES.md`.

## Win condition (first weekend)

Linux kernel booted on J773g via m1n1 chainload (RAM only, driven from a host
over USB-C), reaching a busybox shell on an HDMI display with a USB keyboard.

Stretch: NVMe root, Ethernet, GPU rendering.
Out of scope this weekend: audio, full display controller, installer,
suspend/shutdown, all USB-C/Thunderbolt ports.

## Constraints

- macOS stays intact and bootable. No writes to the internal disk, partition
  table or boot policy without Andrei's explicit approval for that action.
- Dev boots are RAM-only until the win condition works and Andrei approves.
- Raw ADT/ioreg dumps, firmware and logs stay in git-ignored `private/`.
- Never reuse `audio/j713` speaker profiles or safety limits on the mini.
- J773g work goes in new files (`docs/j773g-*.md`, `t8132-j773g.dts`, later
  `audio/j773g/`). Shared files change only for genuine T8132 fixes.

## Phase 1 — setup and recon

| # | Step | Where | Status |
|---|------|-------|--------|
| 1 | Fork `Kb2uka/Omarchy-M4-Native` → `andreinita21/OmarchyM4Mini`, branch `j773g` from `upstream/develop` | mini (macOS) | done 2026-10-13 |
| 2 | macOS recon: ioreg dump + `system_profiler`, confirm Mac16,10 / J773g | mini (macOS) | done 2026-10-13 |
| 3 | Shrink macOS partition, install m1n1 boot stub (reduced security) | mini, **Andrei's approval first** | not started |
| 4 | Clone fork on host, set up m1n1 `proxyclient` | host | not started |
| 5 | Fast incremental kernel builds (Gravity/Asahi M4 tree + T8132 patches) | server | not started |
| 6 | Boot mini into m1n1 proxy mode, dump the real ADT into `private/` | host + mini | not started |
| 7 | **(Fable 5.1, high)** Diff J773g ADT vs J713 findings and J713 DT; write the real `PLAN.md` | host | not started |

## Phase 2 — the boot loop

Subsystem order, one at a time, smallest change per boot:

1. HDMI shell: minimal `t8132-j773g.dts` (CPUs, AIC, PMGR, iBoot framebuffer
   via simplefb) + busybox initramfs.
2. NVMe (ANS, shared with J713 — check power domain fix in
   `docs/j713-nvme-power-domain.md`).
3. USB host + keyboard.
4. PCIe: Ethernet, Wi-Fi (bcm4387 per ioreg; board config and firmware
   selection still to verify).
5. GPU.
6. Display controller (disp0 / dispext0 / dispext1 + display crossbar per
   ioreg; HDMI and Thunderbolt only, no internal panel).
7. Audio, with mini-specific speaker safety data only.

## Phase 3 — later

Real rootfs on SSD, m1n1 stage 2 / U-Boot from disk, Omarchy on top. Each
disk-touching step needs Andrei's approval.

## Open questions (fill in from the live ADT)

- Which USB-C port on the J773g is the m1n1 debug/proxy port (Asahi docs).
- Ethernet controller: not matched by a first ioreg grep; identify its node.
- Whether the SMC shutdown issue (upstream #24) reproduces on the mini.
- Wi-Fi/BT board config string and firmware selection for the mini.
