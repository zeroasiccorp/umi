#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import random
import numpy as np
from switchboard import UmiTxRx


def test_fifo_flex(sumi_dut, random_seed, sb_umi_valid_mode, sb_umi_ready_mode):

    random.seed(random_seed)
    np.random.seed(random_seed)

    # launch the simulation
    sumi_dut.simulate(plusargs=[('valid_mode', sb_umi_valid_mode), ('ready_mode', sb_umi_ready_mode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx("host2dut_0.q", "dut2host_0.q", fresh=True)

    print("### Starting test ###")

    for count in range(1000):
        # length should not cross the DW boundary - umi_mem_agent limitation
        length = np.random.randint(0, 255)
        dst_addr = 32*random.randrange(2**(10-5)-1)  # sb limitation - should align to bus width
        src_addr = 32*random.randrange(2**(10-5)-1)
        data8 = np.random.randint(0, 255, size=length, dtype=np.uint8)
        print(f"[{count}] umi writing {length} bytes to addr 0x{dst_addr:08x}")
        host.write(dst_addr, data8, srcaddr=src_addr, max_bytes=16)
        print(f"[{count}] umi read from addr 0x{dst_addr:08x}")
        val8 = host.read(dst_addr, length, np.uint8, srcaddr=src_addr, max_bytes=16)
        if ~((val8 == data8).all()):
            print(f"ERROR umi read from addr 0x{dst_addr:08x}")
            print(f"Expected: {data8}")
            print(f"Actual: {val8}")
            assert (val8 == data8).all()


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
