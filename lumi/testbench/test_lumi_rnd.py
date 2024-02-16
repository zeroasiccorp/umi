#!/usr/bin/env python3

# Example illustrating how UMI packets handled in the Switchboard Python binding
# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import random
import numpy as np
from pathlib import Path
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx, delete_queue

THIS_DIR = Path(__file__).resolve().parent


def build_testbench(topo="2d", trace=False):
    dut = SbDut('testbench', trace=True, trace_type='fst', default_main=True)

    EX_DIR = Path('..')

    # Set up inputs
    dut.input('testbench_lumi.sv')
    if topo=='2d':
        print("### Running 2D topology ###")
    elif topo=='3d':
        print("### Running 3D topology ###")
    else:
        raise ValueError('Invalid topology')

    for option in ['ydir', 'idir']:
        dut.add('option', option, EX_DIR / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'umi' / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'lambdalib' / 'ramlib' / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'lambdalib' / 'stdlib' / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'lambdalib' / 'vectorlib' / 'rtl')

    # Verilator configuration
    vlt_config = EX_DIR / 'testbench' / 'config.vlt'
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', vlt_config)
#    dut.set('option', 'relax', True)
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '--prof-cfuncs')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-CFLAGS')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-DVL_DEBUG')

    # Build simulator
    dut.build()

    return dut

def main(topo="2d", vldmode="2", rdymode="2", trace=False, host2dut="host2dut_0.q", dut2host="dut2host_0.q", sb2dut="sb2dut_0.q", dut2sb="dut2sb_0.q"):
    # clean up old queues if present
    for q in [host2dut, dut2host, sb2dut, dut2sb]:
        delete_queue(q)

    dut = build_testbench(topo,trace)

    hostdly = random.randrange(500)
    devdly = random.randrange(500)

    # launch the simulation
    dut.simulate(
        plusargs=[
            ('valid_mode', vldmode),
            ('ready_mode', rdymode),
            ('hostdly', hostdly),
            ('devdly', devdly)
        ],
        trace=trace
    )

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    sb = UmiTxRx(sb2dut, dut2sb)
    host = UmiTxRx(host2dut, dut2host)

    print("### Side Band loc reset ###")
    sb.write(0x7000000C, np.uint32(0x00000000), posted=True)

    # Need to add some delay are reassertion before sending things
    # over serial link
    print("### Read local reset ###")
    val32 = sb.read(0x70000000, np.uint32)
    print(f"Read: 0x{val32:08x}")
    assert val32 == 0x00000000

    if topo=='2d':
        width = np.uint32(0x00000000)
        crdt  = np.uint32(0x001A001A)
    if topo=='3d':
        width = np.uint32(0x00030000)
        crdt  = np.uint32(0x00070007)

        linkactive = 0
        while (linkactive == 0):
            print("### Wait for linkactive ###")
            linkactive = sb.read(0x70000004, np.uint32)
            print(f"Read: 0x{val32:08x}")

        linkactive = 0
        while (linkactive == 0):
            print("### Wait for linkactive ###")
            linkactive = sb.read(0x60000004, np.uint32)
            print(f"Read: 0x{val32:08x}")

        print("### disable Tx ###")
        sb.write(0x60000010, np.uint32(0x0), posted=True)
        sb.write(0x70000010, np.uint32(0x0), posted=True)

        import time
        time.sleep (0.1)

        print("### disable Rx ###")
        sb.write(0x70000014, np.uint32(0x0), posted=True)
        sb.write(0x60000014, np.uint32(0x0), posted=True)

        print("### configure loc Rx width ###")
        sb.write(0x70000010, width, posted=True)

        print("### configure rmt Rx width ###")
        sb.write(0x60000010, width, posted=True)

        print("### configure loc Tx width ###")
        sb.write(0x70000014, width, posted=True)

        print("### configure rmt Tx width ###")
        sb.write(0x60000014, width, posted=True)

        print("### Tx init credit ###")
        sb.write(0x60000020, crdt, posted=True)

        print("### Tx init credit ###")
        sb.write(0x70000020, crdt, posted=True)

        print("### Rx enable local ###")
        sb.write(0x70000014, np.uint32(0x1) + width, posted=True)

        print("### Rx enable remote ###")
        sb.write(0x60000014, np.uint32(0x1) + width, posted=True)

        print("### Tx enable remote ###")
        sb.write(0x60000010, np.uint32(0x1) + width, posted=True)

        print("### Tx enable local ###")
        sb.write(0x70000010, np.uint32(0x1) + width, posted=True)

        print("### Tx enable credit ###")
        sb.write(0x60000010, np.uint32(0x11) + width, posted=True)

        print("### Tx enable credit ###")
        sb.write(0x70000010, np.uint32(0x11) + width, posted=True)

    print("### Read loc Rx ctrl ###")
    val32 = sb.read(0x70000014, np.uint32)
    print(f"Read: 0x{val32:08x}")
    #assert val32 == np.uint32(0x1) + width

    print("### Read loc Tx ctrl ###")
    val32 = sb.read(0x70000010, np.uint32)
    print(f"Read: 0x{val32:08x}")
    #assert val32 == np.uint32(0x11) + width

    print("### Read rmt Rx ctrl ###")
    val32 = sb.read(0x60000014, np.uint32)
    print(f"Read: 0x{val32:08x}")
    #assert val32 == np.uint32(0x1) + width

    print("### Read rmt Tx ctrl ###")
    val32 = sb.read(0x60000010, np.uint32)
    print(f"Read: 0x{val32:08x}")
    #assert val32 == np.uint32(0x11) + width

    print("### UMI WRITE/READ ###")

    for count in range (100):
        # length should not cross the DW boundary - umi_mem_agent limitation
        length = np.random.randint(0,511)
        dst_addr = 32*random.randrange(2**(10-5)-1) # sb limitation - should align to bus width
        src_addr = 32*random.randrange(2**(10-5)-1)
        data8 = np.random.randint(0,255,size=length,dtype=np.uint8)
        print(f"umi writing {length+1} bytes to addr 0x{dst_addr:08x}")
        host.write(dst_addr, data8, srcaddr=src_addr)
        print(f"umi read from addr 0x{dst_addr:08x}")
        val8 = host.read(dst_addr, length, np.uint8, srcaddr=src_addr)
        if ~((val8 == data8).all()):
            print(f"ERROR umi read from addr 0x{dst_addr:08x}")
            print(f"Expected:")
            print(f"{data8}")
            print(f"Actual:")
            print(f"{val8}")
            assert (val8 == data8).all()

    print("### TEST PASS ###")

if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--trace', action='store_true', default=False,
                        help="Enable waveform tracing")
    parser.add_argument('--topo', default='2d')
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('--rdymode', default='2')
    args = parser.parse_args()

    main(topo=args.topo,vldmode=args.vldmode,rdymode=args.rdymode,trace=args.trace)
