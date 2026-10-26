# SPDX-License-Identifier: MIT
# m1n1 hypervisor script (run_guest.py -m, after the SPTM/TXM load): point
# the memory controller's CTRR-C window at the guest's relocated region.
#
# SPTM (macOS 27, T8132) halts in init_pre_late_io_reservation with
# "AMCC [...] and ACC [...] CTRR-C regions don't match" when the AMCC CTRR-C
# lower/upper limits differ from the range it derives from the memory map:
# DeviceTree start .. SPTM-rx end (inclusive, 16 KiB pages from dram-base).
# On the mini iBoot leaves CTRR-C unlocked and disabled with a stale window
# (0x1048..0x104a), so the HV can rewrite it for the guest layout.

mm = hv.adt["chosen"]["memory-map"]
lo = mm.DeviceTree[0]
hi = mm.SPTM_rx[0] + mm.SPTM_rx[1] - 1

amcc = u.adt["/chosen/lock-regs/amcc"]
ctrr = amcc["amcc-ctrr-c"]
shift = ctrr.page_size_shift
dram_base = u.adt["/chosen"].dram_base
planes = [ap + i * amcc.plane_stride
          for ap in amcc.aperture_phys_addr
          for i in range(amcc.plane_count)]

for base in planes:
    if p.read32(base + ctrr.lock_reg_offset) & ctrr.lock_reg_mask:
        raise RuntimeError(f"AMCC CTRR-C locked at {base:#x}, cannot relocate")
    p.write32(base + ctrr.lower_limit_reg_offset, (lo - dram_base) >> shift)
    p.write32(base + ctrr.upper_limit_reg_offset, (hi - dram_base) >> shift)

print(f"j773g-sptm: AMCC CTRR-C -> [{lo:#x}-{hi:#x}] on {len(planes)} planes")
