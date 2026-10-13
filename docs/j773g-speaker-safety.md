<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# J773g speaker safety — review notes (no audio enabled)

Status 2026-10-14: **audio stays off.** Every ladder rung disables the
speaker path (`dts/t8132-j773g-ladder.dtsi`) and the kernel fragment
compiles out `SND_SOC_APPLE_T8132_SPEAKER`, `SND_SOC_TAS2764` and
`SND_SOC_APPLE_MCA`. Only the `stock` DTB leaves the audio nodes on, and the
ladder kernel has no driver for them. J713 speaker data is never used here
(START_HERE rule 6).

## Hardware (this mini's ioreg)

- One amplifier, TI **SN012776** (TAS2764 family), i2c3 address 0x38, IRQ
  gpio0 pin 14; shutdown GPIO pin 15 (Gravity DT).
- Feeds a single internal speaker through MCA TX0, ADMAC, audio DART.
- Headphone jack codec: Cirrus CS42L84 on i2c1 0x4b (separate path; no
  speaker-safety concern, not in Gravity's tree yet).

## What Gravity ships (`gravity-m4` 4fc326f6c2)

`sound/soc/apple/t8132/` (`apple,j773g-speaker`, by Niklas Sheth): a
machine driver with **in-kernel** protection instead of Asahi's
userspace `speakersafetyd`:

- A two-node voice-coil/magnet thermal model (`thermal.h`). Every sample
  is "charged" before it enters the DMA ring, so the model leads the
  speaker. Attenuation ramps in 0.5 dB steps and mutes on fault or DMA stall.
- Thermal constants: from the **J773g AID36 / AUSP_0329 ATSP preset**,
  decoded with upstream speakersafetyd's `audump.py`. r_coil 40 °C/W,
  r_magnet 60 °C/W, tau_coil 3.4 s, tau_magnet 210 s, ambient 50 °C,
  control target 140 °C, hard bound 150 °C, stall bound 180 °C.
- Electrical values are **module parameters marked as assumptions awaiting
  measurement**: full scale 17 V peak at DVC 0, minimum 4 Ω, 200 % margin.
- A hardware volume ceiling of `ceiling_dvc` = 20 half-dB steps
  (**−10 dB**) by default. The amp's gain, ISENSE/VSENSE, OCE and HPF
  controls are locked from userspace.
- Status in sysfs: running/faulted, coil and magnet temperature estimates,
  attenuation, peak.

## Before any audio rung

1. Confirm that this mini's macOS audio device ID is AID36. Tuning data is
   at `/System/Library/Audio/Tunings/AID36/` (exists on this mini); find
   the matching preset, and re-decode the thermal constants independently
   (`audump.py`) to compare with Gravity's numbers.
2. Keep Gravity's −10 dB ceiling and 200 % margin; do not raise
   `ceiling_dvc`.
3. First test: short, quiet signal (pink noise at −30 dBFS, 10 s), with the
   sysfs status read before and after. Stop on `faulted=1` or any coil
   estimate near 140 °C.
4. Record results in NOTES.md before any longer playback.

Until then, the only audio worth testing is HDMI audio (`DRM_APPLE_AUDIO`),
which goes to the display, not the internal speaker.
