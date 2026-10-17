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

## Checklist run (2026-10-17, linux-gravity-m4 pkgrel 6)

1. **Tuning check.** macOS 27.0.1 on the mini has `/System/Library/Audio/
   Tunings/AID3..AID48`; the AID number is not in the IORegistry under an
   obvious name (`speaker-protection = 0`, `speaker-config = 000f0002` on
   `audio-speaker@38`, `audio-control,sn012776`), and `ADM/config.plist` is
   empty. Every AID's `builtin_speaker_out_general.austrip` was decoded with
   speakersafetyd's `docs/audump.py` (its parameter dump goes to stderr).
   Active profile ("speakerType A", channel assignment all):

   | | AID36 = AID48 | older 1-speaker desktops (AID6/10/12/25/26/32/33/47) | Gravity driver |
   |---|---|---|---|
   | R coil / magnet (°C/W) | 40 / 60 | 40 / 60 | 40 / 60 |
   | tau coil / magnet (s) | 3.4 / 210 | 3.7 / 250 | 3.4 / 210 |
   | ambient, limit, headroom (°C) | 50, 140, 40 | 50, 140, 40 | 50, 140, hard 150, stall 180 |
   | Re (Ω) | 4.6 | 4.6 | assumes 4.0 |
   | V at full scale | 11.9 | 15.87 | assumes 17 |

   AID36 and AID48 carry the same speaker data, so which of the two this Mac
   uses does not matter; Gravity's constants equal them, and its electrical
   assumptions are stricter even than the older family's.
2. Ceiling and margin unchanged: `ceiling_dvc` 20 (−10 dB), 200 %. The driver
   logs "ceiling -10.0 dB, 14451 mW peak, 900 mW continuous, ramp to
   -12.5 dB". The model starts warm (t_limit − t_window − 1 °C coil) after a
   boot, by design.
3. First test: 10 s pink noise, −30.3 dBFS RMS, peaks capped at −20 dBFS,
   S24_LE mono 48 kHz straight to `hw:T8132Speaker`. Before: running=0,
   faulted=0, coil 83.0 °C (cooling from the warm start), hardware_dvc 200
   (muted). During: running=1, hardware_dvc 20, faulted=0, stalls=0, coil
   82.3 °C. After: running=0, faulted=0, coil 81.5 °C, hardware_dvc 200.
   Andrei heard a clean hiss from the internal speaker.
4. This entry. Speaker autoload enabled after it (the temporary
   `/etc/modprobe.d/91-j773g-speaker-hold.conf` removed).

Asahi's macaudio stays off; Omarchy's speakersafetyd has no J773g config and
is not used (the protection is in the kernel driver).
