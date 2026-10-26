# OmarchyM4Mini — project brief

You are helping Andrei bring Omarchy/Asahi Linux to his **base M4 Mac mini**.
Read this whole file before doing anything, then follow it. Re-read the
"Rules" sections at the start of every session.

---

## 1. Context

- **Target machine:** base **M4 Mac mini — Mac16,10 / J773g / T8132**.
- **Sibling board:** the 13-inch M4 MacBook Air (Mac16,12 / J713) shares the
  SoC; the J713 files in this repo are the shared T8132 platform layer.
- **What carries over (shared SoC):** CPU bring-up, AIC interrupt controller,
  PMGR, GPU rendering, video decoder, SMC basics, NVMe.
- **What differs (board-level, needs new work):**
  - Device tree: J713 nodes do not apply; the J773g tree is built from the
    mini's own ADT.
  - Display: no internal panel; HDMI + Thunderbolt only.
  - No internal keyboard/trackpad/battery (use a USB keyboard).
  - Audio: different single speaker + headphone jack. **Do not reuse the
    `audio/j713` speaker profiles/safety limits on the mini.**
  - Extra I/O: Gigabit Ethernet, front USB-C ports, rear Thunderbolt —
    different wiring, unqualified.
  - Wi-Fi/BT: verify chip, board config and firmware selection.

## 2. Repositories

- **This public repository** is the polished, functional edition: only
  changes verified on the mini land here.
- **The private alpha** is invite-only and very unstable; experiments start
  there.

---

## 3. Rules — safety (non-negotiable)

1. **Never write to the mini's internal disk, partition table or boot policy
   without Andrei's explicit approval for that specific action.** Propose the
   exact command and wait.
2. **macOS must stay intact and bootable** on its own partition at all times.
3. Development boots are **RAM-only** (m1n1 chainload over USB) or from a
   non-default boot entry, until Andrei approves otherwise.
4. Before any risky step, confirm Andrei knows the recovery path: hold power
   for recovery (1TR), DFU restore from another Mac.
5. **Never commit Apple firmware, raw ADT/ioreg dumps, macOS-extracted files,
   Widevine, credentials or personal logs.** Keep them in the git-ignored
   `private/` folder.
6. Do not reuse J713 audio/speaker-safety data on the mini — wrong speaker
   parameters can damage hardware.

## 4. Rules — model and effort

Switch with `/model` and `/effort`.

| Situation | Model | Effort |
|---|---|---|
| Plans, ADT diffs, writing `PLAN.md` | Fable 5.1 | high |
| First draft of a new subsystem's DT nodes (USB-C/TB, display, PCIe) | Fable 5.1 | high |
| Silent hang / boot failure Opus couldn't solve in 2–3 attempts | Fable 5.1 | high |
| Routine loop: small DT tweak, rebuild, read a normal log, update notes | Opus 5.5 | medium |
| Non-obvious boot failure, porting nodes with address/IRQ/power-domain cross-checks | Opus 5.5 | high |
| Git, docs, commit messages | Opus 5.5 | medium |

- Never use maximum-effort or multi-agent fan-out modes for this project; the
  bottleneck is the reboot loop, not thinking.
- Target budget: **~20% Fable, ~80% Opus**. When a Fable session finishes its
  task, write the result into `PLAN.md` / `NOTES.md` and tell Andrei to switch
  back to Opus 5.5.
- If Fable's safeguards block a legitimate step (e.g. hypervisor tracing), do
  that step on Opus 5.5.
- Read specific files; do not scan the whole kernel tree.

## 5. Rules — usage limits (5-hour window)

- Usage resets on a rolling 5-hour window. **When the limit is reached, stop
  and continue the work when the limit resets — do not abandon or restart the
  task.**
- **Keep `NOTES.md` current after every meaningful step** (not only at the
  end), so a resumed session loses nothing.
- When resuming (or in any new session): read `START_HERE.md`, `PLAN.md` and
  the latest `NOTES.md` entry, then continue from "Next step". Do not redo
  finished steps or retry ideas already logged as failed.
- If the weekly limit is close, finish the current step, update notes, and
  tell Andrei instead of starting something new.

## 6. Rules — working style

After every boot attempt, append to `NOTES.md`:

```
## <date time> — attempt N
Model/effort:
Changed:
Result / last log line:
Diagnosis:
Next step:
```

- Add one subsystem at a time. Smallest change per boot attempt.
- Ask before anything irreversible. Propose; Andrei runs hardware steps.
- Hardware steps (power cycles, cables, boot modes) are Andrei's — give him
  exact, short instructions.

## 7. Repo layout and licensing

- Keep J773g work in **new files** next to the J713 ones: `docs/j773g-*.md`,
  `dts/`, `packaging/j773g/`, `tools/j773g/`. Edit shared files only for
  genuine chip-level (T8132) fixes.
- Keep `LICENSE.md`, `LICENSES/` and `THIRD_PARTY_NOTICES.md`. Add an SPDX
  line to every new file:
  - kernel patches: `GPL-2.0-only`
  - device trees: `GPL-2.0+ OR MIT`
  - scripts/tools: `MIT`
  - docs: `CC-BY-4.0` (or MIT)

---

## 8. Phase 1 — setup and recon

**Important:** once the mini boots m1n1/Linux, macOS (and a Claude Code
session on the mini) is not running. The boot loop is driven from a **second
machine (host)** connected to the mini by USB-C on its debug-capable port.

On the mini (macOS):

1. Recon: `ioreg -l -w0 > private/ioreg-j773g.txt` (IORegistry is derived from
   the ADT) and `system_profiler SPHardwareDataType`. Confirm Mac16,10 / J773g.
2. With Andrei's approval only: shrink the macOS partition and install an m1n1
   boot stub (Asahi-style stub partition with reduced security).

On the host:

3. Clone this repo; set up m1n1 `proxyclient` (Python).
4. Set up fast incremental kernel builds (Gravity `gravity-m4` tree).
5. Boot the mini into m1n1 proxy mode; dump the real ADT into `private/`.
6. **(Fable 5.1, high)** Diff the J773g ADT against the J713 findings
   (`docs/t8132-adt-audit.md`, `docs/t8132-gap-analysis.md`) and the J713 DT.
   Produce `PLAN.md`: shared / missing / new nodes, ordered subsystem list.

## 9. Phase 2 — the loop

1. **Edit DT** — minimal `t8132-j773g.dts` first: CPUs, AIC, PMGR, iBoot
   framebuffer (simplefb), busybox initramfs.
2. **Build** — kernel + DTB.
3. **Chainload** — m1n1 Linux loader from the host, RAM only.
4. **Read logs** — if the screen is black, run Linux as a guest under the m1n1
   hypervisor to get a console over USB and trace MMIO.
5. Log to `NOTES.md`, repeat.

Subsystem order: HDMI shell → NVMe → USB host + keyboard → PCIe (Ethernet,
Wi-Fi) → GPU → display controller → audio (with mini-specific safety data).

## 10. Phase 3 — on the SSD

Real rootfs on the SSD, m1n1 stage 2 / U-Boot loading from disk, Omarchy on
top ([docs/j773g-install.md](docs/j773g-install.md)). Only with Andrei's
approval at each disk-touching step.
