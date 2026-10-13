<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Draft upstream issue — not posted

Target: https://github.com/Kb2uka/Omarchy-M4-Native/issues (new issue).
Andrei decides whether and when to post it. Keep it short; the maintainer
asked contributors to identify the exact model and to separate source
inspection from hardware observation.

---

**Title:** Heads-up: J773g (base M4 Mac mini, Mac16,10) port in progress in a fork

Hi kb2uka,

I own a base M4 Mac mini (Mac16,10 / J773g / T8132, firmware 20457.1.29) and
have started a port of this project to it in a fork:
https://github.com/andreinita21/OmarchyM4Mini (branch `j773g`, based on
`develop`).

Plan, in order: RAM-only m1n1 chainload from a host, minimal J773g device
tree (CPUs, AIC, PMGR, simplefb) to a busybox shell over HDMI with a USB
keyboard, then NVMe, USB host, PCIe (Ethernet, Wi-Fi), GPU, display
controller. Audio last, with mini-specific speaker data; I will not reuse the
`audio/j713` profiles or limits.

I intend to keep J773g work in new files (`docs/j773g-*.md`, a
`t8132-j773g.dts`) and only touch shared files for genuine T8132 fixes, which
I would send as small PRs against `develop`. I understand the installer is
J713-only and that nothing here qualifies another model.

Two questions, if you have a minute:

1. Is there anything in the current T8132 patches you already know to be
   J713-specific beyond the obvious panel, keyboard/trackpad, battery and
   speaker nodes?
2. Did you observe the SMC shutdown issue (#24) as chip-level or board-level?

Nothing observed on hardware yet; the fork currently only has the macOS-side
recon. I will report back with results.

Thanks for the groundwork.
