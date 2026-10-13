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
  "git diff --check" on the first commit flags trailing whitespace on ~60
  START_HERE.md lines, all inherited from the source; other files clean.
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

## 2026-10-13 23:35 — setup 1 (preliminary J773g device tree + plan, no hardware)
Model/effort: Fable 5.1 / high
Changed:
- Saved the ADT-derived IODeviceTree plane: private/iodevicetree-j773g.txt
  (ioreg -p IODeviceTree -l -w0, 8878 lines). Git-ignored.
- Found that Asahi's asahi branch (head 77cb8f24c2, 2026-05-30) already has
  arch/arm64/boot/dts/apple/t8132-j773g.dts (commit fbf2e630a9, 2026-07-05:
  compatible apple,j773g, model, framebuffer power domains ps_dispext0_cpu +
  ps_dptx_phy) plus t8132.dtsi / t8132-jxxx.dtsi / t8132-pmgr.dtsi. Fetched
  those eight files read-only into the session scratchpad for comparison
  (not committed; they are GPL-2.0+ OR MIT kernel sources).
- Decoded the mini's PMGR "devices" table (393 x 48-byte records, 16 ps-regs
  entries) with a stand-alone parser using upstream's record layout. Result:
  all 129 providers in t8132-pmgr.dtsi have real (non-virtual) records on
  J773g, register offsets match once the ps-regs base table is applied, and
  the only always-on differences are the three Linux-policy ones (aic,
  disp_sys, disp_fe) also seen on J713. atc2/atc3 are REAL here -> upstream
  patch 0011 must not be applied.
- Wrote dts/t8132-j773g.dts and six layer includes (smc, storage, usb, pcie,
  thunderbolt, display), gated on -DJ773G_LAYER_* so one source builds any
  subset. Every ioreg-derived value is marked UNVERIFIED in the file headers.
- Rewrote PLAN.md as the preliminary plan: J713-vs-J773g table, upstream
  patch applicability, layer table, boot ladder r0..r5, remaining Phase 1
  steps, open questions.
- Memory updated: no Claude attribution in commits is a standing rule.
Result / last log line: no boot attempted; nothing installed; nothing written
  outside the repo. dtc is NOT installed on this mini (brew has it), so the
  DT is syntax-unchecked - that is step 2 of Andrei's list (Opus).
Diagnosis (findings that answer the open questions):
- Ethernet: /arm-io/apcie/pci-bridge2 (apcie-port 2) -> lan-1gb, PCI ID
  14e4:1682 (Broadcom BCM57762 GbE, tg3 driver; same as the M1/M2 mini), own
  DART dart-apcie2 @0x4_92000000 IRQ 1250, mapper reg 1 -> SID 1,
  CLKREQ gpio0 162 func 2, PERST gpio0 165. MAC in /chosen
  mac-address-ethernet0 (m1n1 fills local-mac-address through the alias).
- Display crossbar: display-crossbar0 (compatible display-crossbar,t8132)
  lists dfp-endpoints atc0 atc1 atc2 atc3 lpdptx dptx; the per-port
  atcN-dpxbar muxes are what upstream already models as atcphyN_xbar. HDMI
  path = dispext0 @0x2_84000000 (external) + dcpext0 @0x2_86e00000 (role
  DCPEXT0, IRQs 732/731/734/733) + dptx-phy @0x3_9a740000 (dptx-phy,t8122)
  + dp2hdmi-gpio0: HPD aop-gpio 41, hdmi_pwr_en SMC gP0f (pin 15),
  dp2hdmi_pwr_en SMC gP1a (pin 26), reset SMC gP10 (pin 16), force_dpfu
  aop-gpio 36. SMC function provider phandle 0xf2 = /arm-io/smc/smc-pmu.
- Speaker hardware: ONE amp, TI SN012776 (TAS2764 family) at i2c3 0x38,
  IRQ gpio0 pin 14; jack codec Cirrus CS42L84 at i2c1 0x4b, IRQ gpio0 98;
  MCA (iop-audio-controller) with audio-speaker / audio-codec-output /
  audio-codec-input / mca-loopback children; dp-audio0/1/2 for DP/HDMI.
  Same topology as t8112-j473 (M2 mini). Safety limits must be derived for
  this amp/enclosure; never from audio/j713.
- USB: four ATC instances. atc2 (port-number 3) has no PD controller and
  carries usb2/usb3 hub ports -> GL3590 hub (firmware "usb3hub-fw-gl3590,spi"
  in a NOR flash on spi3 @0x3_ad10c000 IRQ 1057) -> the two front USB-C
  ports. hpm0/hpm1/hpm3 = USIDs 0xC/0xA/0x8, IRQs 11-17-19 / 37-43-45 /
  63-69-71, port-numbers 1/2/4 -> the three rear Thunderbolt ports.
- Wi-Fi: BCM4387 (14e4:4434) module-instance "sakhalin"; BT 14e4:5f72
  (bluetooth,n88). Both on apcie port 0, SIDs 1/2, pins 160/163 (= J713).
- SMC, ANS/NVMe, SART, USB atc0/atc1, DARTs, AIC, UART, wdt, gpio: all
  addresses and IRQs visible in ioreg equal the J713 audit values.
- No MTP / dockchannel-mtp on the mini; i2c0 exists (no children), i2c4
  does not exist.
Next step: Andrei switches to **Opus 5.5 / medium** and runs the rest of his
  2026-10-13 list, in this order:
  (2) brew install dtc (needs his OK - it installs software); cpp+dtc build
      of each layer combination; dtbs_check against the kernel bindings.
  (3) propose the native arm64 build environment (Homebrew LLVM/clang+lld,
      dtc, python3 pyserial+construct, cpio/gzip, busybox source, m1n1
      source), wait for approval, then build kernel + initramfs + m1n1 under
      ~/OmarchyM4Mini/build/ (already git-ignored) or outside the repo.
  (4) tools/j773g-boot.sh (adapt upstream tools/boot.sh: layers -> DTB,
      M1N1DEVICE, logging) and tools/j773g-adt-dump.sh (proxyclient
      dump of the live ADT into private/).
  (5) research: J773g DFU/proxy port, GL3590 hub firmware behaviour, PCIe
      pwren GPIOs, BCM4387 firmware set for sakhalin, SMC shutdown on mini.
  (6) docs/j773g-home-day-checklist.md with exact commands.
  (7) README.md: replace the J713 installer front page with what this fork
      is (mini port, status, layers, no installer, upstream credit) while
      keeping licence/notice files.
  Commit and push after each step; keep NOTES.md current. Back to Fable 5.1
  / high only for Phase 1 step 7 (live ADT diff) or a stuck boot.

## 2026-10-13 23:45 — setup 2 (offline DT validation + build environment)
Model/effort: Opus 5.5 / medium (Andrei asleep; standing approval for
  everything except disk/partition/boot-policy writes and the m1n1 stub)
Changed:
- brew install dtc (1.8.1). Docker Desktop (already installed, arm64,
  10 CPUs, 5.8 GB) is the build environment: native arm64, no cross tools,
  case-sensitive source tree in the Docker volume "j773g-src".
- tools/j773g/Dockerfile (Debian trixie: clang/lld/llvm, dtc, busybox-static,
  dt-schema venv), tools/j773g/inner-build.sh (runs in the container),
  tools/j773g-build.sh (host wrapper: image|src|config|dtbs|check|kernel|
  initramfs|m1n1|all|shell), tools/j773g/kernel.fragment, tools/j773g/init.
  Artifacts land in build/j773g/ (git-ignored).
- src: Asahi linux 77cb8f24c2 (shallow fetch by SHA) + patches 0001-0010,
  0012, 0013, 0015 + m4-boot-hacks-7.1.9 + nvme split-NVMMU: all apply
  cleanly, no fuzz.
- dtbs: ladder rungs generated as wrapper .dts files (r0-boot, r1-smc,
  r2-storage, r3-usb, r4-pcie, r5-atc23, rx-all) and built through kbuild:
  ZERO dtc warnings on every rung. r5-atc23 and rx-all are byte-identical
  (Thunderbolt/display layers emit nothing yet, as designed).
- check (CHECK_DTBS=y, dt-schema): compared to t8132-j713.dtb from the same
  tree (74 unique findings, all "t8132 compatible not in binding" class).
  r0-r3 add nothing new (the dockchannel-hid helper-cpu finding differs only
  by phandle value). r4 adds the pcie2 DART compatible (same class). r5 adds
  the same class for the atc2/atc3 dwc3/DART/atcphy/crossbar nodes, plus one
  real deviation: dwc3_2 (front hub, dr_mode host) has no usb-role-switch,
  which the binding requires. Deliberate (host-only hub port); revisit if
  the driver complains.
- kernel config: arm64 defconfig + fragment; fixed symbol names
  (NVMEM_APPLE_SPMI, TYPEC_SN201202X, MUX_APPLE_DPXBAR); every fragment
  option now sticks.
Result / last log line: no boot attempted; nothing written outside the
  repo, Homebrew and Docker.
Next step: finish kernel Image.gz build, initramfs, m1n1 build; then
  items (4) host scripts, (5) research, (6) home-day checklist, (7) README.

## 2026-10-14 00:30 — setup 3 (kernel/initramfs/m1n1 built; research; Gravity prior art)
Model/effort: Opus 5.5 / medium
Changed:
- Kernel: build/j773g/Image.gz (17 MB, 7.1.9-ge0a31617df5c, arm64 defconfig
  + fragment, ~6 min in Docker). initramfs (busybox 1.37 static, init prints
  probe lines / partitions / links then a shell). m1n1 v2.0.0-27-g94395adc
  (needs Rust now; added to the image) -> build/j773g/m1n1/{m1n1.bin,
  m1n1.macho, proxyclient/}.
- Smoke test: kernel + initramfs boot to the busybox shell under QEMU
  (-M virt -cpu max, inside the build container). Proves init, busybox and
  16K-page kernel are sane; says nothing about Apple hardware.
- tools/j773g-boot.sh (host: rung name -> upstream boot.sh with the kit,
  default panic=0 so a panic stays on HDMI) and tools/j773g-adt-dump.sh
  (host: live ADT + PMGR dumps into private/adt-live-<ts>/).
- README.md rewritten for the fork; upstream front page kept as
  docs/upstream-README.md.
- Research (web): see docs/j773g-research.md. Headline: **GravityLinux has
  a J773g-only installer and a gravity-m4 kernel branch whose
  t8132-j773g.dts is hardware-tested on an M4 mini** (Fedora boots, native
  HDMI via DCP, NVMe, USB incl. front hub, Ethernet, speaker).
- DT changes adopted from Gravity, each cross-checked against our ioreg:
  framebuffer power domain ps_dispext0_cpu -> ps_dispext0_fe (cpu domain is
  firmware-owned/disabled and defers simpledrm = black screen risk on r0);
  port00 pwren-gpios = smc_gpio 19 (INHERITED from Gravity jxxx); Ethernet
  on bus 2 / RID 0x200 (was 3 / 0x300); front hub GPIO hogs 101 (flash OE)
  and 198 (reset), confirmed in our ioreg usb3hub-fw node; port labels
  Back-middle (atc0, DFU port) / Back-left (atc1) / Back-right (atc3).
  Our hpm select IRQs (13/39/65) already equal Gravity's fixed values.
- Wi-Fi is BCM4388 rev C2 (PCI 14e4:4434), not BCM4387 as macOS's
  compatible string suggests. PLAN.md updated.
- Rebuilt all rungs: zero dtc warnings; dt-schema adds only the
  "pinctrl binding has no gpio-hog children" note on r5 (same as Gravity).
Result / last log line: no boot attempted.
Next step: build Gravity's gravity-m4 kernel + its t8132-j773g.dtb as a
  known-good control for the home day; write docs/j773g-research.md and
  docs/j773g-home-day-checklist.md; update PLAN.md.

## 2026-10-14 00:10 — setup 4 (control kernel, docs; offline work finished)
Model/effort: Opus 5.5 / medium
Changed:
- tools/j773g-build.sh gravity: GravityLinux/linux gravity-m4 @ 4fc326f6c2
  (7.1.13) built with our fragment -> build/j773g/gravity/{Image.gz,
  t8132-j773g.dtb}. Has the idle= early_param too. This is the known-good
  control for the first boot (their DT has booted Fedora on an M4 mini).
- M1N1_FLAVOUR=gravity: GravityLinux/bootloader @ 7243b815c4 ->
  build/j773g/m1n1-gravity/. Asahi m1n1 now builds to build/j773g/m1n1/
  from /src/m1n1-asahi (old /src/m1n1 in the volume is unused).
- docs/j773g-research.md (answers PLAN section 7 with sources),
  docs/j773g-home-day-checklist.md (recovery path, host setup, stub route
  options with Gravity installer recommended, proxy-mode stage 2 swap,
  ADT dump, ladder commands, black-screen triage). PLAN.md updated (phase
  table, open questions, Wi-Fi = BCM4388 C2). README status updated.
- Gravity's CDN installer offers one target only: "Gravity Linux 44 KDE —
  M4 developer alpha (20260920)", EFI 500 MB + Boot 1 GB + Root >= 16 GB,
  stub firmware 26.6.2, stage 1 chainloads <ESP>/m1n1/boot.bin.
- GravityLinux/adt-collection has no J773g ADT (J700, J813, J313 only).
- Correction to setup 3: "PLAN.md updated" there happened in this step.
Result / last log line: no boot attempted. Nothing written to the mini's
  disk layout, partitions, boot policy or ESP. Installed software: Homebrew
  dtc; Docker image omarchy-j773g-build; Docker volume j773g-src (~6 GB).
Diagnosis: n/a. Every remaining step needs Andrei (hardware or approval).
Next step (Andrei):
  1. Read docs/j773g-home-day-checklist.md. Decide the stub route (A =
     Gravity installer, recommended) — it shrinks macOS: APPROVAL.
  2. Still pending from setup 0: confirm the repo description
     (gh repo edit) and whether to reflow START_HERE.md; whether to post
     docs/j773g-upstream-issue-draft.md.
  3. Strategic choice after the first control boot: keep Asahi 77cb8f24c2 +
     upstream patches, or rebase the J773g layers on Gravity's gravity-m4.
  4. Phase 1 step 7 (live ADT diff) on Fable 5.1 / high after the dump.
