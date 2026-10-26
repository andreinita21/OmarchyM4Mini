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
- Created andreinita21/OmarchyM4Mini, cloned to ~/OmarchyM4Mini, branch
  j773g pushed to origin.
- Set per-repo git identity (andreinita21, noreply address). Repo policy
  (CLAUDE.md / AGENTS.md / CONTRIBUTING.md) forbids AI attribution in commits
  and PRs; none added.
- Repo description NOT set yet: shown to Andrei for confirmation.
- Copied ~/start_here.md verbatim to START_HERE.md. The source file has lost
  its markdown line structure (headings and bullets run together mid-line);
  content is intact and readable. Reflow pending Andrei's decision.
  "git diff --check" on the first commit flags trailing whitespace on ~60
  START_HERE.md lines, all inherited from the source; other files clean.
- Created PLAN.md (skeleton), NOTES.md. Added private/ to .gitignore.
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
  docs/t8132-gap-analysis.md exist as the brief expects; the raw
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
  entries) with a stand-alone parser using the J713 record layout. Result:
  all 129 providers in t8132-pmgr.dtsi have real (non-virtual) records on
  J773g, register offsets match once the ps-regs base table is applied, and
  the only always-on differences are the three Linux-policy ones (aic,
  disp_sys, disp_fe) also seen on J713. atc2/atc3 are REAL here -> patch 0011 must not be applied.
- Wrote dts/t8132-j773g.dts and six layer includes (smc, storage, usb, pcie,
  thunderbolt, display), gated on -DJ773G_LAYER_* so one source builds any
  subset. Every ioreg-derived value is marked UNVERIFIED in the file headers.
- Rewrote PLAN.md as the preliminary plan: J713-vs-J773g table, patch applicability, layer table, boot ladder r0..r5, remaining Phase 1
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
  atcN-dpxbar muxes are what the T8132 tree already models as atcphyN_xbar. HDMI
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
  (4) tools/j773g-boot.sh (adapt tools/boot.sh: layers -> DTB,
      M1N1DEVICE, logging) and tools/j773g-adt-dump.sh (proxyclient
      dump of the live ADT into private/).
  (5) research: J773g DFU/proxy port, GL3590 hub firmware behaviour, PCIe
      pwren GPIOs, BCM4387 firmware set for sakhalin, SMC shutdown on mini.
  (6) docs/j773g-home-day-checklist.md with exact commands.
  (7) README.md: replace the J713 installer front page with the mini port
      (status, layers, no installer) while keeping licence/notice files.
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

## 2026-10-13 23:58 — setup 3 (kernel/initramfs/m1n1 built; research; Gravity prior art)
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
- tools/j773g-boot.sh (host: rung name -> tools/boot.sh with the kit,
  default panic=0 so a panic stays on HDMI) and tools/j773g-adt-dump.sh
  (host: live ADT + PMGR dumps into private/adt-live-<ts>/).
- README.md rewritten for the mini.
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
  dtc; Docker image omarchy-j773g-build (3.2 GB); Docker volume j773g-src (5.9 GB).
Diagnosis: n/a. Every remaining step needs Andrei (hardware or approval).
Next step (Andrei):
  1. Read docs/j773g-home-day-checklist.md. Decide the stub route (A =
     Gravity installer, recommended) — it shrinks macOS: APPROVAL.
  2. Still pending from setup 0: confirm the repo description
     (gh repo edit) and whether to reflow START_HERE.md.
  3. Strategic choice after the first control boot: keep Asahi 77cb8f24c2 + the T8132 patches, or rebase the J773g layers on Gravity's gravity-m4.
  4. Phase 1 step 7 (live ADT diff) on Fable 5.1 / high after the dump.

## 2026-10-14 01:30 — setup 5 (rebase on GravityLinux gravity-m4)
Model/effort: Opus 5.5 / medium
Decisions (Andrei, 2026-10-14): "go with gravity" -> kernel base =
  GravityLinux/linux gravity-m4; stub route = Gravity installer (route A).
  Mini not reachable for a few days; offline work continues.
Changed:
- Gravity tree vs the J713 kernel: m4-boot-hacks applies cleanly to
  gravity-m4, i.e. Gravity boots J773g WITHOUT those hacks (kept as
  M4_HACKS=1 fallback); split-NVMMU and brcmfmac 4388 patches conflict
  (Gravity has its own T8132 NVMe driver). Gravity's packaged config =
  Asahi Fedora 16K config + small overlays (DRM_ASAHI_M4=m, J773g speaker
  drivers built in, dockchannel earlycon).
- dts/t8132-j773g-ladder.dtsi: gates on top of Gravity's unmodified
  t8132-j773g.dts. Groups SMC/STORAGE/USB/PCIE/CPUFREQ/DISPLAY/GPU; audio
  disabled in every rung. Old Asahi layered tree -> dts/asahi/ (BASE=asahi).
- Build: BASE=gravity default (pinned 4fc326f6c2, 7.1.13), rungs g0-boot ..
  g6-display + stock (Gravity's own DTB). Fragment: + DRM_APPLE=y (needed
  BACKLIGHT_CLASS_DEVICE=y), pstore/ramoops, speaker/TAS2764/MCA drivers =n.
  All fragment options stick. Kernel 7.1.13-g7267e940bada built (~7 min).
- init: prints the previous boot's console from pstore when present.
- Verified offline: each rung adds exactly its group's nodes (DTB walk with
  libfdt); stock adds only audio + agx mailbox; dt-schema: no finding in any
  rung beyond the 39 of Gravity's stock DTB; QEMU smoke boot to the shell OK.
- Found: Gravity's J773g tree has no macsmc-reboot NVMEM cells -> the Air's
  "shutdown restarts" bug is likely present on the mini.
- PLAN.md sections 3-5 and 7, README, home-day checklist rewritten for the
  Gravity base. Legacy Asahi artifacts moved to build/j773g/asahi/.
Result / last log line: no boot attempted; nothing written to the mini's
  disk layout, ESP or boot policy.
Next step: offline items: SMC poweroff NVMEM cells for J773g from this
  mini's ioreg; Wi-Fi 4388 C2 support check in gravity-m4; speaker-safety
  review notes for Gravity's apple,j773g-speaker (documentation only);
  Rust-enabled GPU kernel build.

## 2026-10-14 01:48 — setup 6 (poweroff rung, GPU kernel, Wi-Fi firmware, reviews)
Model/effort: Opus 5.5 / medium
Changed:
- PMU/poweroff: Gravity's T8132 SMC node has no smc-reboot/smc-rtc child
  and there is no main-PMU SPMI node. Added dts/t8132-j773g-pmu.dtsi (nub-
  spmi0 0x3_88714000, Abbey USID 0xe fixed NVMEM, the four shutdown-state
  cells, smc-rtc rtc_offset) - every offset matches
  this mini's ioreg pmu-main@E. Rung g7-poweroff; docs/j773g-poweroff.md.
  Only new schema note: apple,abbey-pmic not in the PMIC binding.
- GPU: Debian rustc 1.85.1 / bindgen 0.71.1 added to the image (kernel
  minimums; rustup 1.99 stays for m1n1). kernel-gpu step builds
  Image-gpu.gz (RUST=y, DRM_ASAHI_M4=y) in a worktree; rung g8-gpu uses it.
  Needs Gravity's m1n1 (supplies T8132 GPU firmware/platform data).
- Wi-Fi: Gravity's brcmfmac already has BSS v116 + C2-as-4388c0 names, so
  the J713 brcmfmac patch is not needed. **This unit's module is V=a,
  antenna X3**; macOS loads P-sakhalin-X3_M-WLMT_V-a__m-4.9.txt. Gravity's
  installer hardcodes the V=u NVRAM (confirmed in its wifi.py) -> wrong
  NVRAM on this mini under Gravity. tools/j773g-wifi-fw.sh copies the
  live macOS selection into private/firmware/brcm (done, git-ignored);
  WITH_FIRMWARE=1 packs it into the initramfs. brcmfmac/cfg80211 now =y.
- Speaker: reviewed Gravity's in-kernel limiter (two-node thermal model,
  constants from the J773g AID36/AUSP_0329 preset, -10 dB ceiling, electrical
  values unmeasured) -> docs/j773g-speaker-safety.md. Audio stays off.
- docs/j773g-gravity-issue-drafts.md (unposted): V=a NVRAM, missing
  reboot/RTC nodes.
- Both kernels and the firmware initramfs smoke-boot in QEMU.
Result / last log line: no boot attempted; nothing written to the mini's
  disk layout, ESP or boot policy (private/firmware is inside the repo).
Next step: hardware (Andrei, when back at the mini): home-day checklist
  route A, then stock -> g0 .. g8. Offline leftovers: confirm the mini's
  audio ID is AID36 and re-decode its speaker preset; Bluetooth calibration
  (BTBF); Phase 3 (Omarchy userland on the Gravity kernel) needs a plan -
  Fable 5.1 / high per START_HERE.

## 2026-10-14 07:20 — setup 7 (Phase 3 plan)
Model/effort: Fable 5.1 / high (plan only, per START_HERE §4)
Changed:
- docs/j773g-phase3-plan.md: Omarchy userland plan on the Gravity kernel.
  Research result that changes the picture: upstream Omarchy merged an
  official Apple Silicon platform on 2026-10-10 (basecamp/omarchy#14431):
  platform `aarch64-apple`, packages omarchy-mac 0.1.4 + omarchy-mac-boot
  20261010 on pkgs.omarchy.org edge/aarch64, boot chain m1n1 -> U-Boot ->
  Limine -> UKI, kernel linux-aurora (Asahi fork, M1/M2), installer
  omacom/omarchy-mac-installer (M4 refused in its catalog, no public
  release yet). Arch Linux ARM has the whole desktop set for aarch64.
- Decision (route O): reuse the official stack; replace only kernel, m1n1
  and U-Boot with packages from the Gravity sources already pinned here
  (linux-gravity-m4 provides linux-asahi, m1n1-gravity, uboot-gravity) +
  a small omarchy-j773g glue package (asahi,efi-system-partition from the
  gravity property via /etc/m1n1.conf, DTBS limited to t8132-j773g,
  omarchy-mac-kernel name shim until an upstream provides-check lands).
  Image: own unsigned builder mirroring omarchy-mac-installer's producer.
  Install: rung u0 (Omarchy root on USB, kernel from RAM, no disk writes)
  first, then replace Gravity's Root + ESP files in place with approval.
  GPU llvmpipe until g8 passes (official M3 precedent); audio off.
  The J713 boot.bin route is the fallback if U-Boot -> Limine fails on
  T8132.
- PLAN.md section 8 summarises it; README points to it.
Result / last log line: no boot attempted; nothing written to the mini's
  disk layout, ESP or boot policy.
Next step: switch back to Opus 5.5 / medium. Offline (can start now):
  P3.1 PKGBUILDs + ALARM build container, P3.2 image builder + QEMU smoke,
  P3.3 Omarchy/Gravity drafts (docs/j773g-omarchy-issue-drafts.md). Hardware
  (Andrei): home-day checklist route A, ladder stock -> g0..g8, then u0.
  Decisions for Andrei: docs/j773g-phase3-plan.md section 8.

## 2026-10-14 08:05 — setup 8 (Phase 3 packaging and image builder)
Model/effort: Fable 5.1 / high (Andrei asked to keep going; P3.1–P3.2 are
  Opus-grade work and the next session should run on Opus 5.5 / medium)
Changed:
- packaging/j773g/: PKGBUILDs linux-gravity-m4 (gravity-m4 7.1.13, asahi-alarm
  linux-asahi config + j773g.fragment, provides linux-asahi, -ARCH
  localversion), m1n1-gravity (bootloader 7243b815c4 + artwork, LOGO=bootlogo),
  uboot-gravity (asahi-v2026.07-2 + asahi-alarm/Omarchy patches + Gravity's
  nine T8132 patches; the spec's four late Asahi NVMe patches are already in
  that base), omarchy-j773g (asahi,efi-system-partition from the Gravity
  property via /etc/m1n1.conf + update-m1n1, DTBS=t8132-j773g only,
  /usr/local/bin/omarchy-mac-kernel shim).
- tools/j773g/Dockerfile.alarm + tools/j773g-pkg.sh: Arch Linux ARM build
  container (rustup 1.93.1, bindgen 0.73.2 from ALARM), makepkg wrapper.
  Built: m1n1-gravity (208 KB), uboot-gravity (254 KB); linux-gravity-m4 in
  progress (long).
- tools/j773g-image.sh + tools/j773g/image-build.sh: image builder mirroring
  omarchy-mac-installer's build-mac-image (btrfs @/@home/@log/@pkg +
  @factory, ext4 /boot, FAT ESP, Limine via lifecycle dispatch); vendored
  finalize-root + node.pin (MIT). tools/j773g-image-smoke.sh: QEMU boot of
  the image inside the container. Neither run yet.
- docs/j773g-image.md, docs/j773g-omarchy-issue-drafts.md (unposted).
Result / last log line: no boot attempted; nothing written to the mini's
  disk layout, ESP or boot policy. Docker Desktop privileged containers have
  loop devices and btrfs (checked), so the image builder can run on the mini.
Next step: finish linux-gravity-m4 and omarchy-j773g builds; run
  tools/j773g-image.sh (expect iterations: omarchy-apply-system in a chroot,
  Limine activation); smoke-boot with tools/j773g-image-smoke.sh; then NOTES.

## 2026-10-14 09:30 — setup 9 (packages built, image boots in QEMU)
Model/effort: Fable 5.1 / high (continuing at Andrei's request)
Changed:
- All four J773g packages build (tools/j773g-pkg.sh all): m1n1-gravity,
  uboot-gravity (asahi-v2026.07-2 base already contains the spec's four late
  Asahi NVMe patches; Gravity's nine apply), linux-gravity-m4 7.1.13.gravity1-3
  (~9 min), omarchy-j773g. Kernel fragment lessons: DRM_APPLE=y needs TYPEC=y
  (modpost on non-exported helpers), BTRFS_FS=y (Mac initramfs hooks mount
  the root before module autoload), PL011 + built-in virtio for QEMU.
- tools/j773g-image.sh builds the image in ~7 min (893 packages, root.img
  12.7 GB, 62 MB UKI, stage 2 = m1n1 + t8132-j773g.dtb + U-Boot). Uses
  Omarchy's fixed disk identities (ESP 4F4D-5801 etc.): omarchy-mac-boot
  hardcodes them.
- tools/j773g-image-smoke.sh: GPT disk (ESP/Boot/Root) on a QEMU virt
  machine with virtio-mmio -> switch root, "Omarchy first boot" finishes,
  owner provisioning starts, `omarchy login:` prompt. Only speakersafetyd
  fails (no speaker hardware, driver compiled out).
- docs/j773g-image.md findings; plan table P3.1/P3.2 done; checklist pointer.
Result / last log line: QEMU: "Finished Omarchy first boot ... omarchy login:".
  No boot attempted on the mini; nothing written to its disk layout, ESP or
  boot policy.
Next step: hardware (Andrei): route A, ladder stock -> g0..g8, then rung u0
  (image on a USB SSD, kernel from RAM). Offline leftovers: J773G_CMDLINE
  from the ladder; posting the Omarchy/Gravity drafts (Andrei); AID36 audio check;
  mesa-gravity-m4 after g8. Switch back to Opus 5.5 / medium.

## 2026-10-14 17:40 — setup 10 (rung u0 tooling, J713 channel, m1n1 console fix)
Model/effort: Fable 5.1 / high (continuing at Andrei's request; switch back to Opus)
Changed:
- Rung u0 (plan P3.4) tooling: tools/j773g/compose-disk.sh builds one sparse
  GPT disk (EFI 500 MB id 4F4D-5801, Boot 2 GiB, Root) from the image plus
  the RAM-boot kit build/j773g/disk/u0/{Image.gz,initramfs.img,cmdline};
  tools/j773g-disk.sh compose|write <disk>|info (write refuses anything but
  a whole external USB disk and asks for the identifier; disk0/disk3 refused
  in a read-only check); tools/j773g-boot.sh u0 (DTB = U0_RUNG, default
  g6-display; BOOT_ARGS + Limine's root= line + J773G_CMDLINE);
  tools/boot.sh BOOT_INITRD. Smoke test now boots the same disk.img with
  -snapshot: reached `omarchy login:` again, only speakersafetyd failed.
  The image's initramfs carries uas/usb-storage/xhci/dwc3/phy-apple-atc
  (checked with lsinitcpio), so a USB root is covered.
- Took in the J713 update channel, connect script and speaker/GStreamer
  packages (all J713-only).
- Adopted dockchannel-tx-bound.patch (test tag test-issue82-dockchannel-1) (m1n1 hung on the logo when nothing drained the
  dockchannel TX FIFO). Applies unchanged to Gravity's m1n1 7243b815; now in
  m1n1-gravity pkgrel 2 and the ladder's build/j773g/m1n1-gravity/m1n1.bin
  (sha 41378d15…). Noted the J713 lesson (GPU power limit differs per
  chip) in plan §7 for g8. Image rebuilt so stage 2 carries the fix.
- Freed ~12 GB of stale smoke copies; after the image rebuild the mini has
  ~30 GiB free (Docker VM disk grows with each build; `docker system prune`
  and build/j773g/image-cache are the levers).
Result / last log line: QEMU smoke on the composed disk: "omarchy login:".
  No boot attempted on the mini; nothing written to its disk layout, ESP or
  boot policy.
Next step: hardware (Andrei): route A, ladder stock -> g0..g8, then
  tools/j773g-disk.sh write <USB SSD> + tools/j773g-boot.sh u0. Offline:
  nothing urgent (J773G_CMDLINE after the ladder; the drafts are Andrei's
  to post).

## 2026-10-17 — setup 11 (Gravity installed on the mini; host moves to the MacBook Pro)
Model/effort: Fable 5.1 / default (status review, no build)
Changed:
- Hardware (Andrei, before this session): Gravity Linux alpha installed on
  the mini from gravitylinux.org (home-day checklist §2, route A) and it
  booted. That proves m1n1 stage 1 + stub + firmware + Gravity's J773g DT on
  this unit. Details of what was exercised (HDMI, USB, Ethernet, Wi-Fi) not
  yet recorded.
- Host is now the MacBook Pro (M4 Pro, macOS 27.0.1). The checkout and the
  whole build/j773g kit (16 GB incl. disk.img) live on the external USB SSD
  "Disk D" (disk4, Kingston XS1000), so no kit copy from the mini is needed.
  pyserial 3.5 + construct 2.10.70 installed (--user). Docker Desktop not
  running on the MacBook; the j773g-src Docker volume is on the mini.
- tools/j773g-disk.sh: macOS 27's diskutil no longer prints "Internal:", so
  `write` refused every disk; now only an explicit "Internal: Yes" refuses.
  New guard: the whole disk behind the repository's volume (APFS physical
  store resolved) is refused on macOS and Linux - the dev SSD passed every
  other check. Tested: disk4 refused (repo), disk3 refused (macOS).
Result / last log line: no ladder boot yet; nothing written to the mini's
  ESP by us (the Gravity installer did its own partitioning with approval).
- Decision (Andrei): Gravity was only a test and is disposable; no second
  USB drive. Rung u0 skipped; §5a done directly. Mini layout as reported:
  macOS 80 GB, the rest Gravity.
- tools/j773g-install.sh (serve on the host, prepare inside Gravity) and
  tools/j773g/install-root.sh (busybox, RAM shell): docs/j773g-install.md.
  prepare sets the ESP volume id 4F4D-5801, overlays Limine/UKI, keeps
  vendorfw/ and boot.bin.gravity, leaves boot.bin = proxy m1n1 and the
  Omarchy stage 2 as boot.bin.omarchy, reformats Boot from boot.img, writes
  omarchy/j773g-install.env. install-root streams root.img over HTTP onto
  Gravity's root (UUID-checked, typed back, sha256 verified) and only then
  switches boot.bin. serve tested locally (MANIFEST, 12.7 GB root.img,
  esp.tar served); prepare/install-root untested until the hardware run.
Result / last log line: serve: MANIFEST with sha256 for root.img, boot.img,
  esp.tar, m1n1.bin, install-root.sh. No boot attempted on the mini.
Next step (hardware, Andrei, docs/j773g-install.md): serve on the MacBook;
  prepare in Gravity; poweroff; proxy mode -> ADT dump, stock, g6-display;
  install-root.sh from the g6 shell; power-cycle into Omarchy first boot.
  Then P3.6. Record what the screen shows after every boot.

## 2026-10-17 — setup 12 (hardware day: prepare done, HDMI dark, two root causes)
Model/effort: Fable 5.1 / default (hardware session from the MacBook)
Changed:
- Hardware (Andrei): serve on the MacBook; prepare ran in Gravity (ESP
  4F4D-5801, Boot reformatted, env written; the mini fetched esp.tar,
  boot.img, m1n1.bin). Mini on USB (back-middle) -> proxy mode OK, ADT dump
  OK (private/adt-live-*). HDMI stayed black on every boot.
- Root cause 1 (m1n1): iBoot hands the stub a 640x1136 dummy framebuffer on
  this unit even with the monitor on (the picker route did not change it);
  m1n1 then tries its own DCP bring-up and the DCP crashes ("AFK: ring
  buffer size mismatch", IOP crashed, dcp-iboot failed). Gravity builds both
  stages with NO_DISPLAY=1 (packages' m1n1-no-display.patch "Required for M4
  Mac mini bring-up", installer build.sh). Our proxy m1n1 and the packaged
  stage 2 lacked it. Fix: NO_DISPLAY=1 in tools/j773g/inner-build.sh
  (gravity flavour) and packaging/j773g/m1n1-gravity/PKGBUILD (pkgrel 3);
  rebuilt build/j773g/m1n1-gravity/m1n1.bin (shows "display: skip
  configuration (NO_DISPLAY)", proxy runs, no DCP crash). Stage 2 recomposed
  as new m1n1 + the old DTB/U-Boot tail (build/j773g/image/esp/m1n1/boot.bin;
  the old one kept as m1n1-gravity/boot.bin.omarchy-dcpcrash). New
  tools/j773g/esp-fix-macos.sh (served) replaced boot.bin, boot.bin.proxy
  and boot.bin.omarchy on the mini's ESP from macOS (old ones *.dcpcrash).
  Expected from now on: proxy mode = black HDMI; the kernel lights it.
- Blind-boot tooling: build/j773g/initramfs-net.cpio.gz (init = tools/j773g/initramfs-net.init:
  eth0 via udhcpc, probe output + dmesg to the host on TCP 9999 every 5 s,
  telnetd on 23; j773g_host= on the cmdline) with a `nc -l 9999` loop on the
  host (build/j773g/logs/netlog/). Boot: BOOT_INITRD=... BOOT_ARGS="...
  panic=10 j773g_host=HOST" tools/j773g-boot.sh stock stock-net. Verdict in
  under a minute without a screen. busybox `reboot` from that shell took the
  mini down but it did not come back (reboot path unproven, g7 territory);
  power-cycle by hand.
- Root cause 2 (kernel, stock rung with Gravity's DT): "platform
  30ae00000.dcp: devices misses supplier soc:audio-controller" (Gravity's DT
  has the dpaudio node enabled; our ladder config has no driver for it, so
  fw_devlink blocks apple-dcp). With fw_devlink=permissive apple-dcp probes
  and then defers forever: "Failed to get dp-phy: -517" -
  CONFIG_PHY_APPLE_DPTX was not set in tools/j773g/kernel.fragment; the
  mini's HDMI sits behind apple,t8122-dptx-phy. Our own DTs (g6, packaged)
  keep audio-controller disabled in the ladder but enabled in the packaged
  DTB; the package config has DRM_APPLE_AUDIO=y (binds dpaudio) and
  PHY_APPLE_DPTX=m, and the image's UKI initramfs carries no phy-apple-dptx
  module, so the installed system would light HDMI late or never.
  Fix: CONFIG_PHY_APPLE_DPTX=y in both fragments (ladder and package).
  Builds started on the MacBook: ladder src/config/dtbs/kernel
  (build/j773g/kernel-dptx-build.log), then the ALARM container image,
  linux-gravity-m4 package and the image.
- Side findings: mini = Mac16,10, Ethernet BCM57762 (tg3) works in the stock
  rung (DHCP .95), NVMe p1..p7 seen, Logitech USB receiver enumerates.
  The stock rung needs fw_devlink=permissive with our config (dpaudio).
Result / last log line: netlog stock-net-devlink: "apple-dcp 30ae00000.dcp:
  Failed to get dp-phy: -517 ... deferred probe pending".
Next step: ladder kernel with DPTX -> g6-display over the proxy (HDMI must
  light); rebuild linux-gravity-m4 + image; re-serve; install-root.sh from
  the g6 shell; first boot. Record the screen after every boot.
- Hardware (continued): ladder kernel with PHY_APPLE_DPTX=y -> g6-display
  lights HDMI (1920x1200@60, appledrm fb0, shell + Logitech keyboard). The
  stock rung needs fw_devlink=permissive (Gravity's DT, dpaudio). The
  busybox initramfs has no blkid: install-root.sh now reads fs UUIDs from the
  superblocks (btrfs/ext4/FAT) and takes sizes/sha from the live MANIFEST;
  Boot (1 GiB) is refilled from boot.tar (the image's /boot files) instead
  of dd'ing the 2 GiB boot.img. install-root.sh wrote and verified root.img;
  a power-cycle before it finished left the ESP FAT dirty (invalid cluster
  chain on boot.bin.omarchy) -> tools/j773g/esp-repair-macos.sh (diskutil
  repairVolume + refresh + switch) and esp-switch.sh (RAM shell).
- Root cause 3 (installed system): the Omarchy stage 2 (m1n1 -> U-Boot ->
  Limine -> UKI) boots black and resets in a loop (iBoot then shows "The
  version of macOS on the selected disk needs to be reinstalled" for the
  stub; pick the Linux volume in the picker to boot it again). Proxy boot of
  the UKI's own kernel + initrd + packaged DTB onto the installed root:
  black with the UKI command line, Omarchy up (DHCP .95 after 21 s) with
  "nosmp idle=nop" added. The UKI cmdline = KERNEL_CMDLINE[default] in
  /etc/default/limine, derived from /etc/default/grub before finalize_root
  added J773G_CMDLINE, so the image never carried the ladder's options.
  Fix: image-build.sh patches KERNEL_CMDLINE[default] before the UKI is
  built; image rebuilt with J773G_CMDLINE="nosmp idle=nop"; esp-switch.sh
  also fixes /etc/default/limine and grub on the installed root and
  refreshes an outdated EFI/Linux (MANIFEST line uki.sha256).
- Busybox telnetd in the RAM shell needs /dev/pts (initramfs-net.init
  mounts devpts now); m1n1 proxyclient linux.py picks compression from the
  file suffix (Image.gz, not a bare "linux").
- First boot of the installed system (2026-10-17, ~14:50): Omarchy boots on
  its own (m1n1 -> U-Boot -> Limine -> UKI, HDMI up) and the owner setup
  refuses: "This Mac was set up to encrypt its disk, but the disk was not
  encrypted" (omarchy-mac-boot provision.sh). omarchy-mac-first-boot consumes
  /boot/efi/omarchy/install.conf (the Mac installer app writes it); MISSING
  means encrypt=1. Our ESP never had one. The initramfs carries the
  omarchy-mac-encrypt hook (it needs /boot/omarchy/luks-key to convert).
  Fix: image-build writes esp/omarchy/install.conf (format=1, encrypt=0);
  prepare asks "Encrypt the Linux disk at first boot? [y/N]" (J773G_ENCRYPT
  answers), records ENCRYPT in j773g-install.env, writes install.conf and,
  for yes, stages a 64-byte throwaway luks-key on Boot; install-root.sh and
  esp-switch.sh write install.conf from ENCRYPT (default off). Encrypt=1 is
  wired but untested on the J773g. Andrei's decision: no encryption, but
  the setup must offer the choice. A hand fix of the consumed copy
  (/var/lib/omarchy/mac-first-boot/install.conf encrypt=0 + reboot) did not
  get the owner setup through on the mini (error not read yet; log is
  /var/log/omarchy-provision-owner.log). Next: re-run part 3 from the g6
  shell with the rebuilt image, then first boot; read that log if it fails.
- ESP corruption, second round (2026-10-17 ~16:40): after the macOS
  repairVolume the same invalid cluster chain (i_pos 398218) came back on
  m1n1/boot.bin.omarchy, and install-root's final cp of boot.bin did not
  survive a remount (boot.bin read as the proxy m1n1 again -> proxy mode on
  the real boot). The J773g NVMe has 4096-byte logical sectors; the FAT the
  Gravity installer / fatlabel left was not trustworthy. New
  tools/j773g/esp-reformat.sh (RAM shell, served): saves vendorfw/, omarchy/,
  m1n1/boot.bin.gravity + .proxy, ubootefi.var and Gravity's leftovers to
  RAM (busybox tar has no --exclude: copy by name), busybox mkdosfs (FAT32,
  4096 B/sector), volume id 4F4D-5801 written into sector 0 (and the
  BkBootSec slot at 6*bytes-per-sector), restore, image EFI/ + limine.conf +
  stage 2, install.conf, boot.bin = stage 2, every sha verified after a
  clean remount. Ran clean at 16:45; vendorfw reads back.
- Re-install from the g6 shell done at 16:27 through telnetd (initramfs-net
  with devpts): install-root.sh now accepts a root that already carries
  Omarchy's UUID (re-install), takes the typed answer from stdin (a file;
  /dev/stdin does not exist there), run with setsid so a dropped telnet does
  not kill it (busybox has no nohup).
- First boot after setup, black greeter (2026-10-17 ~18:00, over SSH after
  opening ufw 22/tcp and enabling sshd from the g6 shell; the installed
  system is up as markIV, DHCP .95): HDMI connector connected+enabled, SDDM
  + Hyprland greeter + Xwayland running, but the kernel's asahi_m4 driver
  bound the M4 GPU (card0 + renderD128) and Hyprland rendered through it:
  "DRM_IOCTL_ASAHI_SUBMIT render failed" / "[Hyprland] export failed" in a
  loop, nothing on screen. Fix: /etc/modprobe.d/90-j773g-no-gpu.conf
  (blacklist asahi_m4 + install /bin/false) and a clean reboot -> only
  card1 (display-subsystem), Mesa falls back (zink fails, llvmpipe), no
  submit errors, greeter up. rmmod asahi_m4 on the live system crashed the
  kernel (reboot, and the uncommitted modprobe.d write was lost: btrfs
  30 s commit) - do not unload it live. image-build.sh now ships the
  blacklist and journald Storage=persistent (Omarchy's default journal is
  volatile; the g6-shell chroot found no journal files). ufw: default DROP,
  only 53317 open; 22/tcp added by hand in /etc/ufw/user.rules on the mini
  (not in the image).

## Setup 12 (2026-10-17 evening): targets after the first installed boot

Targets: multicore, poweroff, Wi-Fi, GPU, native USB-C video. SSH: Linux andrei@192.168.100.95 (key
installed); macOS on the mini has Remote Login on, same IP, different host
keys (use -o HostKeyAlias=markIV-macos). Startup disk set to the Gravity
stub from macOS (bless --mount "/Volumes/Gravity Linux" --setBoot); after a
failed boot iBoot falls back to macOS, from where the ESP (disk0s4,
/Volumes/EFI) can be fixed over SSH.

- Wi-Fi: not a mini problem. "Homenetwork 5G" router (192.168.0.1) answers
  ARP/ping but returns "Destination Net Unreachable" and refuses DNS: its
  uplink is down (other devices fail too). On "andrei 5G": HE160, -70 dBm,
  247 Mbit/s download, DNS and HTTPS fine. NM priorities: andrei 5G 20,
  andrei 2.4G 10. brcmfmac still logs join_pref -52 (harmless so far).
- Poweroff: FIXED and verified (docs/j773g-poweroff.md). The PMU dtsi is in
  linux-gravity-m4 pkgrel 5; on the mini the DTB was installed by hand into
  /usr/lib/modules/7.1.13-1-4-ARCH/dtbs (stock copy in /root/j773g-backup)
  until pkgrel 5 is built and installed. A pacman update of the pkgrel 4
  kernel would bring the stock DTB back (no breakage, poweroff regresses).
- Multicore: the live /proc/iomem has a 384 KiB System RAM gap at
  0x10002e28000..0x10002e87fff between the phram/ADT region
  (0x10002db8000 + 0x70000) and the reserved boot image at 0x10002e88000:
  the M4 Air's TrustCache layout (docs/j713-smp-trustcache.md). Gravity's
  m1n1 reserves only the 48 KiB CTRR range, not CTRR_D. A patch reserving
  CTRR_D from s3_0_c11_c0_2/3 in dt_set_memory (m1n1 pkgrel 4) booted
  black and reset into iBoot's "needs to be reinstalled": no journal, no
  pstore. Same stage 2 with the unpatched m1n1 boots. Patch unwired, kept
  as packaging/j773g/m1n1-gravity/ctrr-d-reserve.patch. Next: proxy session
  (USB-C cable connected) to read CTRR_D and the ADT memory-map live and
  boot with a per-boot reservation, as tools/air_trustcache.py does.
  idle=nop stays (cpuidle-apple has no T8132; WFI loses state).
- Limine: extra entry "Omarchy SMP test" (same UKI, no nosmp, loglevel=7,
  panic=10) appended to /boot/efi/limine.conf; default_entry unchanged.
  Backup /root/j773g-backup/limine.conf.pre-smp. limine-entry-tool may drop it.
- GPU (research, not tried): Gravity's asahi_m4 gates on mBoot-18000.161.10,
  which this mini has; the SUBMIT failures fit stock Arch Mesa (treats
  G16 as G14). Path: package GravityLinux/mesa main @ 87ac51d411
  (ES 3.0, ASAHI_MESA_DEBUG=nocompress) under /opt first, Hyprland env only.
- speakersafetyd fails at every boot (start-limit-hit); not touched.
- Multicore: FIXED (2026-10-17 ~21:15), all ten cores on the installed boot
  path. Kernel line: `idle=nop nohlt arm64.nowfxt efi=noruntime`, no
  `splash`. How it was found (proxy RAM boots, tools/j773g/trustcache.py,
  netlog initramfs with tg3 from an overlay cpio, build/j773g/smp/):
  - CTRR_D (s3_0_c11_c0_2/3) reads 0 on every core of the mini; the Air's
    TrustCache reservation does not apply. TrustCache does sit between ADT
    and BootKC-rw and moves every boot. The failed m1n1 pkgrel 4 would only
    have printed "Ignoring CTRR_D"; its reset loop has another cause
    (suspect: rustup pulled a newer toolchain for that build; unverified).
  - SMP + idle=nop: hard hang before userspace, even maxcpus=2, no panic
    path (SOFTLOCKUP/HARDLOCKUP detectors are not built). nosmp boots.
  - idle=nop nohlt arm64.nowfxt (GravityLinux kiwi-descriptions
    workstation.xml, upstream m1n1 3a69c73/9095a5e): 10 CPUs over the proxy,
    Omarchy up, 60 s 10-core load + 4 GB tmpfs churn, no oops. The Gravity
    kernel's __delay still uses wfit; our Air kernel had it patched out.
  - Through U-Boot -> Limine -> UKI the same line hung again: efi=noruntime
    fixes it (U-Boot's EFI runtime services with secondaries up), and
    Plymouth's `splash` hangs it too (verbose and `quiet` without splash
    boot; the same initramfs and splash boot fine over the proxy).
  - Limine passes each entry's cmdline to the UKI (Secure Boot off), so
    test entries work; the menu is invisible (NO_DISPLAY: HDMI lights only
    with the kernel), so a test entry is selected by default_entry for one
    boot and /etc/systemd/system/j773g-limine-default-reset.service (on the
    mini, not in the image) sets default_entry back to 2 after every
    successful boot. A hung test needs macOS (startup options) to edit
    /Volumes/EFI/limine.conf.
  - Do not run limine-update on a proxy-booted system: without EFI it drops
    the UKI and writes a `protocol: linux` entry.
  - Restart from Linux works with the PMU cells (busybox reboot -f and
    systemctl reboot both come back).
  - The mini's /etc/default/grub is the source of the cmdline
    (omarchy-mac-limine-cmdline derives KERNEL_CMDLINE on limine-update).
    Backups in /root/j773g-backup/.
- Security: UFW logs SYNs from public addresses to 5900 on .95, so the
  router (192.168.100.1) forwards to the mini (DMZ or port forward); SSH has
  password login on both Linux and macOS. Andrei will check the router.
- GPU: WORKS (2026-10-17 ~22:50), verified across a reboot. Greeter,
  Hyprland session and Wayland clients render on "Apple M4 (G16G B1)"
  (GLES 3.0); glmark2-es2-wayland correct in a window (score ~1850-2200),
  glmark2-es2-drm ~3400; no GPU faults. Pieces:
  - asahi_m4 (gravity-m4 kernel) accepts mBoot-18000.161.10; m1n1 fills
    apple,m4-core-mask 0x3ff, max-power 37237 mW, freq/voltage tables.
  - mesa-gravity-m4 (GravityLinux/mesa gravity-alpha-02) in /opt/mesa-gravity,
    first through /etc/ld.so.conf.d/00-mesa-gravity-m4.conf. /etc/environment:
    ASAHI_MESA_DEBUG=nocompress MESA_GLES_VERSION_OVERRIDE=3.0
    MESA_GLSL_VERSION_OVERRIDE=300 AQ_NO_RENDERD_FALLBACK=1.
  - Hyprland on the render node (aquamarine's "sole renderD" fallback) into
    buffers allocated on apple-drm: black screen with cursor, even a red
    background never reached HDMI (grim screenshots read back white). Through
    the KMS fd (kmsro, like glmark2-es2-drm) it works: aquamarine 0.15.1-3
    adds AQ_NO_RENDERD_FALLBACK (packaging/j773g/aquamarine-j773g).
  - Wayland clients then got llvmpipe (main device card1 has no render
    node): mesa-gravity-m4 pkgrel 2 falls back to the only render node.
    Arch's eglinfo/es2gears carry RUNPATH=/usr/lib and bypass ld.so.conf
    (test with LD_LIBRARY_PATH=/opt/mesa-gravity/lib).
  - Loading asahi_m4 early (udev coldplug / modules-load.d) hung the boot
    with ten cores (no journal). j773g-gpu.service loads it by name after
    udev settle and card1, before sddm (7.0 s on the mini); modprobe.d keeps
    only "blacklist asahi_m4" so udev does not autoload it.
  - Both packages are pinned in /etc/pacman.conf IgnorePkg on the mini (and
    in the image): an aquamarine without the patch brings the black screen
    back. A future upstream aquamarine/Hyprland update needs the patch
    carried (or upstreamed as an env switch).
  - Backups: /root/j773g-backup/ (pacman.conf, environment, old blacklist).
- My helper sudo() { echo 2006 | sudo -S ...; } plus `| sudo tee` writes
  EMPTY files (the password line replaces the pipe); use sudo sh -c.
- Audio (2026-10-17 ~23:40): internal speaker and 3.5 mm jack WORK.
  - Speaker: Gravity's protected T8132 driver (snd-t8132-speaker, card
    T8132Speaker, PipeWire "Built-in Audio Mono"), kernel pkgrel 6.
    Checklist in docs/j773g-speaker-safety.md (AID36/AID48 tuning decoded,
    -10 dB ceiling kept, quiet first test). Quieter than macOS by design.
  - Jack: kernel pkgrel 7 (j773g-headphones.patch + t8132-j773g-headphones.dtsi,
    the J713 cluster-2 card), omarchy-j773g 20261017 (UCM +
    WirePlumber hook). Codec "CS42L84, Revision: 36"; jack detect works;
    tones left/right correct; music clean; unplug -> speaker, plug ->
    headphones. Headset mic route present, untested (3-pole headphones).
  - New drivers were first loaded by hand (temporary modprobe.d holds,
    now removed); both autoload at boot.
