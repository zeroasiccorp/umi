#!/usr/bin/env python3

# Example illustrating how UMI packets handled in the Switchboard Python binding
# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import time
import numpy as np
from switchboard import UmiTxRx
import pytest


def test_lumi_rnd(lumi_dut, chip_topo, random_seed, sb_umi_valid_mode, sb_umi_ready_mode):

    np.random.seed(random_seed)

    hostdly = np.random.randint(500)
    devdly = np.random.randint(500)
    topo = chip_topo

    # launch the simulation
    lumi_dut.simulate(
        plusargs=[
            ('valid_mode', sb_umi_valid_mode),
            ('ready_mode', sb_umi_ready_mode),
            ('hostdly', hostdly),
            ('devdly', devdly)
        ]
    )

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    sb = UmiTxRx("sb2dut_0.q", "dut2sb_0.q", fresh=True)
    host = UmiTxRx("host2dut_0.q", "dut2host_0.q", fresh=True)

    print("### Side Band loc reset ###")
    sb.write(0x7000000C, np.uint32(0x00000000), posted=True)

    # Need to add some delay are reassertion before sending things
    # over serial link
    print("### Read local reset ###")
    val32 = sb.read(0x70000000, np.uint32)
    print(f"Read: 0x{val32:08x}")
    assert val32 == 0x00000000

    if topo == '2d':
        width = np.uint32(0x00000000)
        crdt = np.uint32(0x001A001A)
    if topo == '3d':
        width = np.uint32(0x00030000)
        crdt = np.uint32(0x00070007)

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

    print("### Read loc Tx ctrl ###")
    val32 = sb.read(0x70000010, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read rmt Rx ctrl ###")
    val32 = sb.read(0x60000014, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read rmt Tx ctrl ###")
    val32 = sb.read(0x60000010, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### UMI WRITE/READ ###")

    for count in range(100):
        # length should not cross the DW boundary - umi_mem_agent limitation
        length = np.random.randint(0, 511)
        dst_addr = 32*np.random.randint(2**(10-5))  # sb limitation - should align to bus width
        src_addr = 32*np.random.randint(2**(10-5))
        data8 = np.random.randint(0, 255, size=length, dtype=np.uint8)
        print(f"umi writing {length+1} bytes to addr 0x{dst_addr:08x}")
        host.write(dst_addr, data8, srcaddr=src_addr)
        print(f"umi read from addr 0x{dst_addr:08x}")
        val8 = host.read(dst_addr, length, np.uint8, srcaddr=src_addr)
        if ~((val8 == data8).all()):
            print(f"ERROR umi read from addr 0x{dst_addr:08x}")
            print(f"Expected: {data8}")
            print(f"Actual: {val8}")
            assert (val8 == data8).all()

    print("### Read loc Tx req credit unavailable ###")
    val32 = sb.read(0x70000030, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read loc Tx resp credit unavailable ###")
    val32 = sb.read(0x70000034, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read loc Tx req credit available ###")
    val32 = sb.read(0x70000038, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read loc Tx resp credit available ###")
    val32 = sb.read(0x7000003C, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read rmt Tx req credit unavailable ###")
    val32 = sb.read(0x60000030, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read rmt Tx resp credit unavailable ###")
    val32 = sb.read(0x60000034, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read rmt Tx req credit available ###")
    val32 = sb.read(0x60000038, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### Read rmt Tx resp credit available ###")
    val32 = sb.read(0x6000003C, np.uint32)
    print(f"Read: 0x{val32:08x}")

    print("### TEST PASS ###")


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
