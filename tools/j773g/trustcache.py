#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Live TrustCache reservation for the M4 Mac mini (J773g) over the m1n1 proxy.

  trustcache.py --proxyclient DIR probe
      Read-only: CTRR (A) and CTRR_D bounds, the ADT /chosen/memory-map
      DeviceTree / TrustCache / BootKC-rw entries and RAM bounds.
  trustcache.py --proxyclient DIR --output-dtb NEW.dtb boot -- <linux.py args>
      Run proxyclient tools/linux.py with the TrustCache range added to the
      DTB as a /memreserve/ entry for this boot only (tools/air_trustcache.py's
      method, for J773g; the CTRR_D-in-m1n1 patch reset-looped, NOTES.md).

M1N1DEVICE must name the mini's proxy tty. Nothing is written to the mini's
storage; the reservation exists only in the DTB handed to this one kernel.
"""

import argparse
import hashlib
import json
from pathlib import Path
import runpy
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import air_trustcache as air  # noqa: E402  (shared DTB parsing and checks)

PAGE = air.PAGE
A_LOWER, A_UPPER = (3, 0, 11, 0, 0), (3, 0, 11, 0, 1)


def read_state(proxy, utils):
    model = utils.adt['/product'].unique_model
    memory = utils.adt['/chosen/memory-map']._properties
    state = {'chip': hex(proxy.get_chipid()), 'model': model,
             'ram': [hex(utils.ba.phys_base), hex(utils.ba.mem_size)]}
    for name in ('DeviceTree', 'TrustCache', 'BootKC-rw'):
        if name in memory:
            state[name] = [hex(x) for x in memory[name]]
    state['ctrr_a'] = [hex(utils.mrs(A_LOWER)), hex(utils.mrs(A_UPPER))]
    state['ctrr_d'] = [hex(utils.mrs(air.D_LOWER)), hex(utils.mrs(air.D_UPPER))]
    return state


def live_range(proxy, utils):
    if proxy.get_chipid() != 0x8132 or utils.adt['/product'].unique_model != 'J773gAP':
        raise ValueError('only the J773g/T8132 mini is supported')
    memory = utils.adt['/chosen/memory-map']._properties
    adt, adt_size = air.checked_range(memory['DeviceTree'], 'ADT')
    start, size = air.checked_range(memory['TrustCache'], 'TrustCache')
    image, image_size = air.checked_range(memory['BootKC-rw'], 'boot image')
    physical, total = air.checked_range((utils.ba.phys_base, utils.ba.mem_size), 'RAM')
    lower, upper = utils.mrs(air.D_LOWER), utils.mrs(air.D_UPPER)
    if not (adt + adt_size == start and start + size == image):
        raise ValueError('TrustCache is not between ADT and the boot image')
    if not (physical <= adt < image + image_size <= physical + total):
        raise ValueError('boot allocations are outside reported RAM')
    if any(x % PAGE for x in (adt, adt_size, start, size, image, image_size)) or size > 16 * 1024 * 1024:
        raise ValueError('unexpected allocation alignment or TrustCache size')
    if lower != adt or upper != start + size - 0x1000:
        raise ValueError('CTRR_D bounds do not match the complete ADT/TrustCache allocation')
    return start, size


def j773g_compatible(data, fields):
    # Stands in for air.root_compatible, which accepts only apple,j713.
    tree, strings, strings_size = fields[2], fields[3], fields[8]
    blob = data[tree:strings + strings_size]
    if b'apple,j773g\0' not in blob or b'apple,t8132\0' not in blob:
        raise ValueError('DTB does not identify J773g/T8132')


def reserve(data, start, size):
    saved = air.root_compatible
    air.root_compatible = j773g_compatible
    try:
        return air.reserve(data, start, size)
    finally:
        air.root_compatible = saved


def prepare(proxy, utils, address, original, evidence):
    start, size = live_range(proxy, utils)
    header = utils.iface.readmem(address, 40)
    total = struct.unpack_from('>I', header, 4)[0]
    if not 40 <= total <= air.MAX_DTB:
        raise ValueError('invalid target DTB size')
    source = utils.iface.readmem(address, total)
    output = reserve(source, start, size)
    with evidence.open('xb') as saved:
        saved.write(output)
    destination = utils.malloc(len(output))
    utils.iface.writemem(destination, output)
    if utils.iface.readmem(destination, len(output)) != output:
        raise RuntimeError('reserved DTB upload verification failed')
    print('TRUSTCACHE_RESERVATION ' + json.dumps({
        'address': hex(start), 'size': hex(size), 'evidence': str(evidence),
        'input_sha256': hashlib.sha256(source).hexdigest(),
        'output_sha256': hashlib.sha256(output).hexdigest(),
    }), flush=True)
    return original(proxy, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('mode', choices=('probe', 'boot'))
    parser.add_argument('--proxyclient', type=Path, required=True)
    parser.add_argument('--output-dtb', type=Path)
    parser.add_argument('linux_args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not (args.proxyclient / 'm1n1/proxy.py').is_file():
        parser.error('--proxyclient must be an m1n1 proxyclient directory')
    sys.path.insert(0, str(args.proxyclient.resolve()))

    if args.mode == 'probe':
        sys.argv = [sys.argv[0]]
        from m1n1.setup import p, u  # connects to M1N1DEVICE
        state = read_state(p, u)
        print('J773G_TRUSTCACHE_PROBE ' + json.dumps(state), flush=True)
        try:
            start, size = live_range(p, u)
            print(f'reservation: {start:#x} + {size:#x}')
        except ValueError as error:
            print(f'no reservation: {error}')
        return

    forwarded = args.linux_args[1:] if args.linux_args[:1] == ['--'] else args.linux_args
    if args.output_dtb is None or args.output_dtb.exists() or not args.output_dtb.parent.is_dir():
        parser.error('--output-dtb must be a new file in an existing directory')
    from m1n1.proxy import M1N1Proxy
    original = M1N1Proxy.kboot_prepare_dt

    def guarded(proxy, address):
        return prepare(proxy, sys.modules['m1n1.setup'].u, address, original, args.output_dtb)

    M1N1Proxy.kboot_prepare_dt = guarded
    linux = args.proxyclient / 'tools/linux.py'
    sys.argv = [str(linux), *forwarded]
    runpy.run_path(str(linux), run_name='__main__')


if __name__ == '__main__':
    main()
