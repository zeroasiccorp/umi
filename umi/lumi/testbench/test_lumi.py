#!/usr/bin/env python3

# Example illustrating how UMI packets handled in the Switchboard Python binding
# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import time
import random
import numpy as np
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx, delete_queue
import umi


def build_testbench(topo="2d", trace=False):
    dut = SbDut('testbench', trace=False, trace_type='fst', default_main=True)

    # Set up inputs
    dut.input('lumi/testbench/testbench_lumi.sv', package='umi')
    if topo == '2d':
        print("### Running 2D topology ###")
    elif topo == '3d':
        print("### Running 3D topology ###")
    else:
        raise ValueError('Invalid topology')

    dut.use(umi)
    dut.add('option', 'library', ['lumi', 'umi'])
    dut.add('option', 'library', 'lambdalib_auxlib')
    dut.add('option', 'library', 'lambdalib_ramlib')
    dut.add('option', 'library', 'lambdalib_vectorlib')

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', 'lumi/testbench/config.vlt', package='umi')
#    dut.set('option', 'relax', True)
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '--prof-cfuncs')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-CFLAGS')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-DVL_DEBUG')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-Wall')

    # Settings - enable tracing
    dut.set('option', 'trace', False)
    dut.set('tool', 'verilator', 'task', 'compile', 'var', 'trace_type', 'fst')

    # Build simulator
    dut.build()

    return dut


def main(topo="2d", vldmode="2", rdymode="2", trace=False,
         host2dut="host2dut_0.q", dut2host="dut2host_0.q", sb2dut="sb2dut_0.q", dut2sb="dut2sb_0.q"):
    # clean up old queues if present
    for q in [host2dut, dut2host, sb2dut, dut2sb]:
        delete_queue(q)

    dut = build_testbench(topo, trace)

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
        trace=trace,
        args=['+verilator+seed+100']
    )

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    sb = UmiTxRx(sb2dut, dut2sb)
    host = UmiTxRx(host2dut, dut2host)

    # Lumi starts in auto configuration based on the link indication from the phy
    # In 2d mode no need to configure anything!
    # In 3d mode need to take down the link and re-enable it with the right configuration
    print("### Side Band loc reset ###")
    sb.write(0x7000000C, np.uint32(0x00000000), posted=True)
    print("### Read local reset ###")
    val32 = sb.read(0x70000000, np.uint32)
    print(f"Read: 0x{val32:08x}")
    assert val32 == 0x00000000

    if topo == '2d':
        width = np.uint32(0x00000000)
    if topo == '3d':
        width = np.uint32(0x00030000)

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

        time.sleep(0.1)

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

    print("### Read loc Tx ctrl ###")
    val32 = sb.read(0x70000010, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read rmt Rx ctrl ###")
    val32 = sb.read(0x60000014, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read rmt Tx ctrl ###")
    val32 = sb.read(0x60000010, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### UMI WRITES ###")

    # host.write(0x70, np.arange(32, dtype=np.uint8), srcaddr=0x0000110000000000)
    host.write(0x70, np.uint64(0xBAADD70DCAFEFACE), srcaddr=0x0000110000000000)
    host.write(0x80, np.uint64(0xBAADD80DCAFEFACE), srcaddr=0x0000110000000000)
    host.write(0x90, np.uint64(0xBAADD90DCAFEFACE), srcaddr=0x0000110000000000)
    host.write(0xA0, np.uint64(0xBAADDA0DCAFEFACE), srcaddr=0x0000110000000000)
    host.write(0xB0, np.uint64(0xBAADDB0DCAFEFACE), srcaddr=0x0000110000000000)

    # 1 byte
    wrbuf = np.array([0xBAADF00D], np.uint32).view(np.uint8)
    for i in range(4):
        host.write(0x10 + i*8, wrbuf[i], srcaddr=0x0000110000000000)

    # 2 bytes
    wrbuf = np.array([0xB0BACAFE], np.uint32).view(np.uint16)
    host.write(0x40, wrbuf, srcaddr=0x0000110000000000)

    # 4 bytes
    host.write(0x50, np.uint32(0xDEADBEEF), srcaddr=0x0000110000000000)

    # 8 bytes
    host.write(0x60, np.uint64(0xBAADD00DCAFEFACE), srcaddr=0x0000110000000000)

    print("### UMI READS ###")

    # 1 byte - the ebrick_core template does not support unaligned byte accesses
    rdbuf = host.read(0x10, 1, np.uint8, srcaddr=0x0000110000000000)
    val8 = rdbuf.view(np.uint8)[0]
    print(f"Read: 0x{val8:08x}")
    assert val8 == 0x0D

    rdbuf = host.read(0x18, 1, np.uint8, srcaddr=0x0000110000000000)
    val8 = rdbuf.view(np.uint8)[0]
    print(f"Read: 0x{val8:08x}")
    assert val8 == 0xF0

    rdbuf = host.read(0x20, 1, np.uint8, srcaddr=0x0000110000000000)
    val8 = rdbuf.view(np.uint8)[0]
    print(f"Read: 0x{val8:08x}")
    assert val8 == 0xAD

    rdbuf = host.read(0x28, 1, np.uint8, srcaddr=0x0000110000000000)
    val8 = rdbuf.view(np.uint8)[0]
    print(f"Read: 0x{val8:08x}")
    assert val8 == 0xBA

    # 2 bytes
    rdbuf = host.read(0x40, 2, np.uint16, srcaddr=0x0000110000000000)
    val32 = rdbuf.view(np.uint32)[0]
    print(f"Read: 0x{val32:08x}")
    assert val32 == 0xB0BACAFE

    # 4 bytes
    val32 = host.read(0x50, np.uint32, srcaddr=0x0000110000000000)
    print(f"Read: 0x{val32:08x}")
    assert val32 == 0xDEADBEEF

    # 8 bytes
    val64 = host.read(0x60, np.uint64, srcaddr=0x0000110000000000)
    print(f"Read: 0x{val64:016x}")
    assert val64 == 0xBAADD00DCAFEFACE

    val64 = host.read(0x70, np.uint64, srcaddr=0x0000110000000000)
    print(f"Read: 0x{val64:016x}")
    assert val64 == 0xBAADD70DCAFEFACE

    val64 = host.read(0x80, np.uint64, srcaddr=0x0000110000000000)
    print(f"Read: 0x{val64:016x}")
    assert val64 == 0xBAADD80DCAFEFACE

    val64 = host.read(0x90, np.uint64, srcaddr=0x0000110000000000)
    print(f"Read: 0x{val64:016x}")
    assert val64 == 0xBAADD90DCAFEFACE

    val64 = host.read(0xA0, np.uint64, srcaddr=0x0000110000000000)
    print(f"Read: 0x{val64:016x}")
    assert val64 == 0xBAADDA0DCAFEFACE

    val64 = host.read(0xB0, np.uint64, srcaddr=0x0000110000000000)
    print(f"Read: 0x{val64:016x}")
    assert val64 == 0xBAADDB0DCAFEFACE

    print("### TEST PASS ###")


if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--trace', action='store_true', default=False,
                        help="Enable waveform tracing")
    parser.add_argument('--topo', default='2d')
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('--rdymode', default='2')
    args = parser.parse_args()

    main(topo=args.topo,
         vldmode=args.vldmode,
         rdymode=args.rdymode,
         trace=args.trace)
