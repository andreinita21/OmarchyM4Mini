# SPDX-License-Identifier: MIT
# m1n1 hypervisor script (run_guest.py -m): trace what macOS writes to the
# back-right USB-C port's ATC PHY and display crossbar while it lights up a
# DisplayPort monitor (J773g, atc3 = typec/port2 in Linux). Every region of
# the ADT nodes is traced in SYNC mode so writes stay in order with reads.
from m1n1.hv import TraceMode

for path in ("/arm-io/atc-phy3", "/arm-io/atc3-dpxbar"):
    if path.split("/")[-1] in hv.adt["/arm-io"]:
        print(f"j773g-dp: tracing {path}")
        trace_device(path, TraceMode.SYNC)
    else:
        print(f"j773g-dp: {path} not in the ADT")
