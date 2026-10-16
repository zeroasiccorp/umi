#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import numpy as np
from switchboard import UmiTxRx

UMI_REQ_ATOMICCAS = 9   # umi_messages.vh


def test_mem_agent(sumi_dut, apply_atomic, random_seed, sb_umi_valid_mode, sb_umi_ready_mode):

    np.random.seed(random_seed)

    # launch the simulation
    sumi_dut.simulate(plusargs=[('valid_mode', sb_umi_valid_mode), ('ready_mode', sb_umi_ready_mode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx("host2dut_0.q", "dut2host_0.q", fresh=True)

    print("### Starting test ###")

    avail_datatype = [np.uint8, np.uint16, np.uint32]
    # a CAS data word holds two operands
    cas_datatype = [np.uint16, np.uint32, np.uint64]

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
        atomicopcode = np.random.randint(0, 10)
        if atomicopcode == UMI_REQ_ATOMICCAS:
            # compare and swap: the data word is twice the operand, the
            # new value in the low half, the compare value in the high
            # half (README 3.4.6); the compare matches half of the time
            bits = 8*(2**wordindexer)
            new = int(np.random.randint(0, maxrange, dtype=np.uint64))
            cmp = int(data[0]) if np.random.randint(0, 2) else \
                int(np.random.randint(0, maxrange, dtype=np.uint64))
            atomicdata = cas_datatype[wordindexer]((cmp << bits) | new)
            print(f"umi atomic CAS new={new:#x} cmp={cmp:#x} of type {avail_datatype[wordindexer]} "
                  f"to addr 0x{addr:08x}")
            atomicval = int(host.atomic(addr, atomicdata, atomicopcode))
            if atomicval >> bits:
                print(f"ERROR umi CAS high half of the response is not zero: {atomicval:#x}")
                assert (atomicval >> bits) == 0
            atomicval &= maxrange - 1
            temp_data = new if int(data[0]) == cmp else int(data[0])
        else:
            atomicdata = np.random.randint(0, 256, dtype=avail_datatype[wordindexer])
            print(f"umi atomic opcode: {atomicopcode} of type {avail_datatype[wordindexer]} "
                  f"to addr 0x{addr:08x}")
            atomicval = host.atomic(addr, atomicdata, atomicopcode)
            temp_data = apply_atomic(data[0], atomicdata, atomicopcode, maxrange)
        if not (atomicval == data[0]):
            print(f"ERROR umi atomic from addr 0x{addr:08x} expected {data[0]} actual {atomicval}")
            assert (atomicval == data[0])
        data[0] = np.array(temp_data).astype(avail_datatype[wordindexer])

        print(f"umi read from addr 0x{addr:08x}")
        val = host.read(addr, length+1, dtype=avail_datatype[wordindexer])
        if not (np.array_equal(val, data)):
            print(f"ERROR umi read from addr 0x{addr:08x} expected {data} actual {val}")
            assert (np.array_equal(val, data))


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
