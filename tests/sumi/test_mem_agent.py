#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import numpy as np
from switchboard import UmiTxRx


def test_mem_agent(sumi_dut, apply_atomic, sb_umi_valid_mode, sb_umi_ready_mode):

    # launch the simulation
    sumi_dut.simulate(plusargs=[('valid_mode', sb_umi_valid_mode), ('ready_mode', sb_umi_ready_mode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx("host2dut_0.q", "dut2host_0.q", fresh=True)

    print("### Starting test ###")

    avail_datatype = [np.uint8, np.uint16, np.uint32]

    # un-aligned accesses
    for _ in range(100):
        addr = np.random.randint(0, 512)
        # length should not cross the DW boundary - umi_mem_agent limitation
        length = np.random.randint(0, 256)
        wordindexer = np.random.choice([0, 1, 2])
        maxrange = 2**(8*(2**wordindexer))
        data = np.random.randint(0, maxrange, size=(length+1), dtype=avail_datatype[wordindexer])
        addr = addr*(2**wordindexer) & 0x1FF

        print(f"umi writing {length+1} words of type {avail_datatype[wordindexer]} to addr 0x{addr:08x}")
        host.write(addr, data)
        atomicopcode = np.random.randint(0, 9)
        atomicdata = np.random.randint(0, 256, dtype=avail_datatype[wordindexer])
        print(f"umi atomic opcode: {atomicopcode} of type {avail_datatype[wordindexer]} to addr 0x{addr:08x}")
        atomicval = host.atomic(addr, atomicdata, atomicopcode)
        if not (atomicval == data[0]):
            print(f"ERROR umi atomic from addr 0x{addr:08x} expected {data[0]} actual {atomicval}")
            assert (atomicval == data[0])
        temp_data = apply_atomic(data[0], atomicdata, atomicopcode, maxrange)
        data[0] = np.array(temp_data).astype(avail_datatype[wordindexer])

        print(f"umi read from addr 0x{addr:08x}")
        val = host.read(addr, length+1, dtype=avail_datatype[wordindexer])
        if not (np.array_equal(val, data)):
            print(f"ERROR umi read from addr 0x{addr:08x} expected {data} actual {val}")
            assert (np.array_equal(val, data))


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
