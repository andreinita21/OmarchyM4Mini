# OmarchyM4Mini — kickoff brief for Claude Code You are helping Andrei port the experimental Omarchy/Asahi 
Linux work for the M4 MacBook Air to his **base M4 Mac mini**. Read this whole file before doing anything, 
then follow it. Re-read the "Rules" sections at the start of every session. --- ## 1. Context - **Upstream 
project:** https://github.com/Kb2uka/Omarchy-M4-Native
  (by studioxradio aka kb2uka). Experimental Linux bring-up for the **M4 MacBook Air 13" — Mac16,12 / J713 
  / T8132**. Early alpha. Its installer is J713-only and must refuse other boards. Release downloads are 
  private.
- **Target machine:** base **M4 Mac mini — Mac16,10 / J773g / T8132**.
  Same SoC as the Air, different board. - **What carries over (shared SoC):** CPU bring-up, AIC interrupt 
controller,
  PMGR, GPU rendering, video decoder, SMC basics, NVMe. - **What differs (board-level, needs new work):** 
  - Device tree: J713 nodes do not apply; a J773g tree must be built from the
    mini's own ADT.
  - Display: no internal panel; HDMI + Thunderbolt only. Upstream still uses
    simpledrm for scanout (no full DCP support).
  - No internal keyboard/trackpad/battery (use USB keyboard; trackpad AFE
    issues are irrelevant).
  - Audio: different single speaker + headphone jack. **Do not reuse the
    `audio/j713` speaker profiles/safety limits on the mini.**
  - Extra I/O: Gigabit Ethernet, front USB-C ports, rear Thunderbolt —
    different wiring, unqualified.
  - Wi-Fi/BT: verify chip, board config and firmware selection. - Shutdown via SMC likely has the same 
  open issue as the Air (upstream #24).
## 2. Goal for the first weekend **Win condition:** Linux kernel booted on J773g via m1n1 chainload, 
reaching a busybox shell on an HDMI display with a USB keyboard. Stretch: NVMe root, Ethernet, GPU 
rendering. Out of scope this weekend: audio, full display controller, installer, suspend/shutdown, all 
USB-C/TB ports. --- ## 3. Rules — safety (non-negotiable) 1. **Never write to the mini's internal disk, 
partition table or boot policy
   without Andrei's explicit approval for that specific action.** Propose the exact command and wait. 2. 
**macOS must stay intact and bootable** on its own partition at all times. 3. Development boots are 
**RAM-only** (m1n1 chainload over USB). No installing
   to disk until the win condition works from RAM and Andrei approves. 4. Before any risky step, confirm 
Andrei knows the recovery path: hold power
   for recovery (1TR), DFU restore from another Mac. 5. **Never commit Apple firmware, raw ADT/ioreg 
dumps, macOS-extracted files,
   Widevine, credentials or personal logs.** Keep them in a git-ignored `private/` folder. 6. Do not reuse 
J713 audio/speaker-safety data on the mini — wrong speaker
   parameters can damage hardware. ## 4. Rules — model and effort Switch with `/model` and `/effort`. 
Fable 5.1 needs Claude Code ≥ 2.1.250. | Situation | Model | Effort | |---|---|---| | Initial plan, ADT 
diff J773g vs J713, writing `PLAN.md` | Fable 5.1 | high | | First draft of a new subsystem's DT nodes 
(USB-C/TB, display, PCIe) | Fable 5.1 | high | | Silent hang / boot failure Opus couldn't solve in 2–3 
attempts | Fable 5.1 | high | | Routine loop: small DT tweak, rebuild, read a normal log, update notes | 
Opus 5.5 | medium | | Non-obvious boot failure, porting nodes with address/IRQ/power-domain cross-checks | 
Opus 5.5 | high | | Git merges/conflicts, docs, commit messages | Opus 5.5 | medium | - Never use 
maximum-effort or multi-agent fan-out modes for this project; the
  bottleneck is the reboot loop, not thinking. - Fable usage on Max is capped at half the weekly allowance 
and burns faster.
  Target budget: **~20% Fable, ~80% Opus**. - When a Fable session finishes its task, write the result 
into `PLAN.md` /
  `NOTES.md` and tell Andrei to switch back to Opus 5.5. - If Fable's safeguards block a legitimate step 
(e.g. hypervisor tracing), do
  that step on Opus 5.5. - Read specific files; do not scan the whole kernel tree. ## 5. Rules — usage 
limits (5-hour window) - Usage resets on a rolling 5-hour window. **When the limit is reached, stop
  and continue the work when the limit resets — do not abandon or restart the task.** - To make that 
seamless, **keep `NOTES.md` current after every meaningful
  step** (not only at the end), so a resumed session loses nothing. - When resuming after a reset (or in 
any new session): read `START_HERE.md`,
  `PLAN.md` and the latest `NOTES.md` entry, then continue from "Next step". Do not redo finished steps or 
  retry ideas already logged as failed.
- If the weekly limit is close, finish the current step, update notes, and
  tell Andrei instead of starting something new. ## 6. Rules — working style - After every boot attempt, 
append to `NOTES.md`:
  ``` ## <date time> — attempt N Model/effort: Changed: Result / last log line: Diagnosis: Next step: ``` 
- Add one subsystem at a time. Smallest change per boot attempt. - Ask before anything irreversible. 
Propose; Andrei runs hardware steps. - Hardware steps (power cycles, cables, boot modes) are Andrei's — 
give him
  exact, short instructions. --- ## 7. Step 0 — fork the repo (do this first) Run from macOS on the mini 
(needs `git` and GitHub CLI `gh`, logged in as Andrei: `gh auth status`; if missing: `brew install gh && 
gh auth login`). ```bash gh repo fork Kb2uka/Omarchy-M4-Native --fork-name OmarchyM4Mini --clone cd 
OmarchyM4Mini git remote -v # origin = Andrei's fork, upstream = Kb2uka # if upstream is missing: git 
remote add upstream https://github.com/Kb2uka/Omarchy-M4-Native.git git fetch upstream git switch -c j773g 
upstream/develop git push -u origin j773g ``` Then: - Set the repo description (ask Andrei to confirm 
first):
  ```bash gh repo edit --description "Experimental Linux bring-up for the base M4 Mac mini (Mac16,10 / 
  J773g / T8132): device trees, kernel patches and boot notes, based on Omarchy-M4-Native. Not an 
  installer." ```
- Copy this file into the repo root as `START_HERE.md`, create `PLAN.md`,
  `NOTES.md`, and add `private/` to `.gitignore`. Commit on `j773g`. - Draft (do not post) an upstream 
issue telling kb2uka a J773g port is in
  progress; Andrei decides whether to post it. ## 8. Repo layout and licensing - Keep J773g work in **new 
files** next to J713 ones:
  `docs/j773g-*.md`, a `t8132-j773g.dts`, later `audio/j773g/`. Edit shared files only for genuine 
  chip-level (T8132) fixes — those become small upstream PRs.
- Keep upstream's `LICENSE.md`, `LICENSES/` and `THIRD_PARTY_NOTICES.md`.
  Add an SPDX line to every new file: - kernel patches: `GPL-2.0-only` - device trees: `GPL-2.0+ OR MIT` - 
  scripts/tools: `MIT` - docs: `CC-BY-4.0` (or MIT)
## 9. Syncing with upstream Before each work session: ```bash git fetch upstream git switch j773g git 
merge upstream/develop ``` - On conflicts: resolve keeping both intents, `git add`, `git commit`, then
  **rebuild and test-boot before pushing**. - Prefer merge. Rebase only before preparing an upstream PR, 
then
  `git push --force-with-lease`. - Single upstream fix only: `git cherry-pick <hash>`. --- ## 10. Phase 1 
— setup and recon **Important:** once the mini boots m1n1/Linux, macOS (and this Claude Code session on 
the mini) is not running. The boot loop must be driven from a **second machine (host)** — Andrei's laptop 
or server — connected to the mini by USB-C on its debug-capable port (check Asahi docs for the J773g 
port). Do the macOS-side prep here, then continue the loop from the host with this same repo. On the mini 
(macOS): 1. Fork (Step 0). 2. Recon from macOS: `ioreg -l -w0 > private/ioreg-j773g.txt` (IORegistry is
   derived from the ADT) and `system_profiler SPHardwareDataType`. Confirm Mac16,10 / J773g. 3. With 
Andrei's approval only: shrink the macOS partition and install an
   m1n1 boot stub (Asahi-style stub partition with reduced security). On the host: 4. Clone the fork; set 
up m1n1 `proxyclient` (Python). 5. Set up fast incremental kernel builds (Gravity/Asahi M4 tree + upstream
   T8132 patches) on Andrei's server. 6. Boot the mini into m1n1 proxy mode; dump the real ADT into 
`private/`. 7. **(Fable 5.1, high)** Diff J773g ADT vs upstream's J713 findings
   (`docs/t8132-adt-audit.md`, `docs/t8132-gap-analysis.md`) and the J713 DT. Produce `PLAN.md`: shared / 
   missing / new nodes, ordered subsystem list.
## 11. Phase 2 — the loop 1. **Edit DT** — start minimal `t8132-j773g.dts`: CPUs, AIC, PMGR, iBoot
   framebuffer (simplefb), busybox initramfs. 2. **Build** — kernel + DTB on the server. 3. **Chainload** 
— m1n1 Linux loader from the host, RAM only. 4. **Read logs** — if the screen is black, run Linux as a 
guest under the
   m1n1 hypervisor to get console over USB and trace MMIO. 5. Log to `NOTES.md`, repeat. Subsystem order: 
HDMI shell → NVMe → USB host + keyboard → PCIe (Ethernet, Wi-Fi) → GPU → display controller → audio 
(with mini-specific safety data). ## 12. Phase 3 — later Real rootfs on SSD, m1n1 stage 2 / U-Boot loading 
from disk, Omarchy on top (follow upstream's installer/image docs). Only with Andrei's approval at each
disk-touching step.
