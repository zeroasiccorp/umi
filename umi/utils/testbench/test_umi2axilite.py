#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import random
import numpy as np
from switchboard import SbDut, UmiTxRx
from umi import sumi


def main():

    extra_args = {
        '--vldmode': dict(type=int, default=1, help='Valid mode'),
        '--rdymode': dict(type=int, default=1, help='Ready mode'),
    }

    dut = SbDut('testbench', cmdline=True, extra_args=extra_args,
                trace=False, default_main=True)

    # Set up inputs
    dut.input('utils/testbench/testbench_umi2axilite.sv', package='umi')

    dut.use(sumi)

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config',
            'utils/testbench/config.vlt',
            package='umi')

    # Build simulator
    dut.build()

    # launch the simulation
    dut.simulate(plusargs=[('valid_mode', dut.args.vldmode),
                           ('ready_mode', dut.args.rdymode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx("host2dut_0.q", "dut2host_0.q", fresh=True)

    print("### Statring test ###")

    for count in range(1000):
        # length should not cross the DW boundary - umi_mem_agent limitation
        length = np.random.randint(0, 255)
        dst_addr = 32*random.randrange(2**(10-5)-1)  # sb limitation - should align to bus width
        src_addr = 32*random.randrange(2**(10-5)-1)
        data8 = np.random.randint(0, 255, size=length, dtype=np.uint8)
        print(f"[{count}] umi writing {length} bytes to addr 0x{dst_addr:08x}")
        host.write(dst_addr, data8, srcaddr=src_addr, max_bytes=8)
        print(f"[{count}] umi read from addr 0x{dst_addr:08x}")
        val8 = host.read(dst_addr, length, np.uint8, srcaddr=src_addr, max_bytes=8)
        if ~((val8 == data8).all()):
            print(f"ERROR umi read from addr 0x{dst_addr:08x}")
            print(f"Expected: {data8}")
            print(f"Actual: {val8}")
            assert (val8 == data8).all()

    print("### TEST PASS ###")


if __name__ == '__main__':
    main()
