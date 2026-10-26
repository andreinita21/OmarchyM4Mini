<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Draft reports for Omarchy's Mac repositories (NOT posted — Andrei decides)

Written 2026-10-14 while planning Phase 3 (`docs/j773g-phase3-plan.md`).
Nothing has booted yet; post these only once the packages in
`packaging/j773g/` have been exercised on the mini, or earlier if the
maintainers prefer to hear about M4 work in progress.

---

## 1. omacom/omarchy-mac-pkgs: `omarchy-mac-kernel` should accept any package that provides `linux-asahi`

`omarchy-mac-boot/bin/omarchy-mac-kernel` matches installed package names
against `^linux-(asahi|aurora)$`. A kernel for a board Asahi and Aurora do
not cover yet (here: the M4 Mac mini, `apple,j773g`, from GravityLinux's
`gravity-m4` tree) has to be named one of those two to pass, or carry a
`/usr/local/bin` shim in front of the real command. Both are fragile.

Suggestion: accept the installed package that provides `linux-asahi`
(`pacman -Qq` + `pacman -Qi` "Provides", or `pacman -Qqs '^linux-'` filtered
by `expac -Q %P`), still requiring exactly one match. Every Asahi-family
kernel already declares `provides=(linux-asahi=…)` (linux-aurora does), so
nothing changes for existing Macs. Patch available on request; the mini's
current workaround is `packaging/j773g/omarchy-j773g/omarchy-mac-kernel` in
andreinita21/OmarchyM4Mini.

Related: the image builder's `candidate-trust/policy.json` refuses every
kernel but `linux-aurora`. A documented way to build a lab image with another
kernel package (the policy's `boot` group as a parameter) would let other
boards use the producer instead of mirroring it.

## 2. omacom/omarchy-mac-installer: `apple,j773g` note for `supported-models.json`

`scripts/supported-models.json` refuses M4 via `apple,j614s` ("M4 and later
Macs are not supported"). For the record: the base M4 Mac mini
(`apple,j773g`, Mac16,10, T8132) has a hardware-tested Linux tree in
GravityLinux/linux `gravity-m4` (Fedora remix, DCP HDMI, NVMe, USB, Ethernet,
GPU driver `DRM_ASAHI_M4`) and a working m1n1 stub installer
(GravityLinux/installer, macOS 26.6.2 firmware). The pinned Asahi installer
engine v0.9.2 has no T8132 chip entry, so the app cannot plan it yet; the
Gravity installer accepts a local `installer_data.json` and can install an
Omarchy image in the meantime. An `apple,j773g` entry in `refused` with that
reason would save the next person the research.

## 3. GravityLinux: see `docs/j773g-gravity-issue-drafts.md`

(V=a Wi-Fi NVRAM alias; missing SMC reboot/RTC nodes on T8132.)
