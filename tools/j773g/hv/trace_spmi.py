# SPDX-License-Identifier: MIT
# m1n1 hypervisor debug script (run_guest.py -m): trace the guest's SPMI
# controller accesses (every /arm-io node whose name starts with nub-spmi).
for node in hv.adt["/arm-io"]:
    if node.name.startswith("nub-spmi"):
        trace_device(f"/arm-io/{node.name}", TraceMode.SYNC)
        print(f"j773g-spmi: tracing /arm-io/{node.name}")
