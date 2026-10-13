<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Draft reports for GravityLinux (NOT posted — Andrei decides)

Two findings from preparing the J773g bring-up on 2026-10-14. Both are
offline findings (this mini's macOS IORegistry plus Gravity's sources) and
have not been tested under Linux yet.

---

## 1. installer: Wi-Fi NVRAM alias is fixed to module vendor `V-u`

**Repo:** GravityLinux/installer, `gravity_firmware/wifi.py`, `MACHINE_ALIASES["j773g"]`

The J773g alias maps `brcm/brcmfmac4388c0-pcie.txt` to
`C-4388__s-C2/P-sakhalin-X0_M-WLMT_V-u__m-4.9.txt`. On my M4 Mac mini
(Mac16,10, macOS 27.0.1) the module reports vendor **`a`**, and macOS loads
a different NVRAM:

```
"ModuleInfo" = "chip='s=C2' module='M=WLMT m=4.9   V=a' prod='17460' manuf='5348'"
{"Firmware"="C-4388__s-C2/sakhalin.trx",
 "NVRAM"="C-4388__s-C2/P-sakhalin-X3_M-WLMT_V-a__m-4.9.txt",
 "Regulatory"="C-4388__s-C2/sakhalin-X3.clmb",
 "TxCap"="C-4388__s-C2/sakhalin-X3.txcb", ...}
```

`P-sakhalin_M-WLMT_V-a__m-4.9.txt` and `…_V-u__…` have different contents
(SHA-256 prefixes `69ca24d1f7fa` vs `395ebc6465ef` in macOS 27.0.1). The
antenna SKU here is X3; X0/X3 `.clmb`/`.txcb` resolve to the same files, so
only the vendor matters. With the fixed alias, `V=a` units get the `V=u`
NVRAM (calibration / transmit power for the other module vendor).

Suggestion: pick the NVRAM from the `V` value (OTP / `HWIdentifiers`), the
same way macOS does, or ship both and select at install time. A reference
script that reads the live selection is `tools/j773g-wifi-fw.sh` in
andreinita21/OmarchyM4Mini.

---

## 2. linux (gravity-m4): no SMC reboot/poweroff or RTC child on T8132

**Repo:** GravityLinux/linux, `arch/arm64/boot/dts/apple/t8132.dtsi` (4fc326f6c2)

The `smc` node has only `gpio` and `hwmon` children, and there is no main
PMU (`nub-spmi0` @ `0x3_88714000`, Abbey @ USID `0xe`) node. So
`macsmc-reboot` and `macsmc-rtc` never bind: no SMC poweroff handler and no
RTC. On the M4 Air the same gap first hung on shutdown; adding the reboot
child without NVMEM cells made Shut Down restart instead
(Kb2uka/Omarchy-M4-Native#24, fixed by #48 with four PMU scratchpad cells).

The mini's ioreg shows exactly the Air's PMU layout (`info-leg_scrpad`
0xf800, `info-pm_setting` 0x2001, `info-clock_offset` 0x2100/6,
`info-fault_shadow` 0x867b/0x10, `info-scrpad_socd` 0x8b00/0x1800).
Proposed nodes (pending a hardware test on J773g):
`dts/t8132-j773g-pmu.dtsi` in andreinita21/OmarchyM4Mini. Since Abbey is
the T8132 PMU on every board, the right home is `t8132.dtsi`. The PMIC
binding would also need `apple,abbey-pmic`.
