<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# NOTES — running log for the J773g port

Append one entry per setup step or boot attempt (format from
`START_HERE.md` section 6). Newest entry at the bottom. A resumed session
reads `START_HERE.md`, `PLAN.md` and the last entry here, then continues
from its "Next step".

## 2026-10-13 23:16 — setup 0 (Step 0 fork + macOS recon)
Model/effort: Fable 5.1 / high
Changed:
- Verified tooling: gh 2.100.0 logged in as andreinita21, git 2.54.0.
- Forked Kb2uka/Omarchy-M4-Native as andreinita21/OmarchyM4Mini, cloned to
  ~/OmarchyM4Mini. Remotes: origin = fork, upstream = Kb2uka (both present
  from the fork command). Branch j773g created from upstream/develop
  (f4112c6, "Merge pull request #62: J713 CPU die temperature") and pushed
  to origin.
- Set per-repo git identity (andreinita21, noreply address). Repo policy
  (CLAUDE.md / AGENTS.md / CONTRIBUTING.md) forbids AI attribution in commits
  and PRs; none added.
- Repo description NOT set yet: shown to Andrei for confirmation.
- Copied ~/start_here.md verbatim to START_HERE.md. The source file has lost
  its markdown line structure (headings and bullets run together mid-line);
  content is intact and readable. Reflow pending Andrei's decision.
- Created PLAN.md (skeleton), NOTES.md, docs/j773g-upstream-issue-draft.md
  (not posted). Added private/ to .gitignore.
- Recon (read-only): system_profiler and sysctl report Mac16,10, hw.target
  J773gAP, Apple M4, 10 cores (4P+6E), 16 GB, firmware 20457.1.29.
  Provisioning UDID prefix 00008132 confirms T8132. ioreg top node:
  target-type "J773g", compatible "J773gAP","Mac16,10","AppleARM".
- Saved private/ioreg-j773g.txt (ioreg -l -w0, 34315 lines, 4.5 MB) and
  private/system_profiler-hardware.txt. Both contain serial numbers; both
  git-ignored.
- Quick compatible-string inventory from the ioreg dump (for PLAN.md):
  arm-io,t8132; aic,3; pmgr1,t8132; mcc,t8132; gpu,t8132; apcie,t8132 +
  apciec,t8132 x3 (Thunderbolt PCIe) + pciec-bridge x3; usb-drd,t8132 x4;
  atc-phy,t8132 x4; atc-dpphy,t8132 x3; dock,usb-c x3; wlan-pcie,bcm4387;
  bluetooth,n88; disp0,t8132 + dispext0,t8132 + dispext1,t8132 +
  display-crossbar,t8132 + dcp-expert-v1 x3; admac,t8132 x2;
  usb3hub-fw-gl3590,spi (GL3590 USB hub, firmware over SPI, likely the
  front USB-C/rear USB-A fan-out); wdt,t8132; smc-pmu, smc-tempsensor,
  smc-charger-util x3. No Ethernet controller matched the first grep; find
  its node from the live ADT.
Result / last log line: no boot attempted. Nothing written to disk outside
  the repo. Partitions, boot policy and m1n1 stub untouched.
Diagnosis: n/a (setup step). Note: docs/t8132-adt-audit.md and
  docs/t8132-gap-analysis.md exist upstream as the brief expects; the raw
  J713 captures they cite are withheld (recon/README.md), so the J773g diff
  will compare against the published audit tables, not the J713 ADT itself.
Next step: Andrei confirms the repo description (gh repo edit) and decides
  on reflowing START_HERE.md; then Phase 1 step 3 (shrink macOS partition +
  m1n1 stub) only with his explicit approval and recovery path confirmed
  (1TR via power hold, DFU from another Mac). Steps 4–6 run on the host.
  Switch to Opus 5.5 / medium for steps 3–6; back to Fable 5.1 / high for
  step 7 (ADT diff and the real PLAN.md).
