#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import random
import numpy as np
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx, delete_queue, verilator_run
from umi import sumi


def build_testbench():
    dut = SbDut('testbench', trace=False, default_main=True)

    # Set up inputs
    dut.input('utils/testbench/testbench_umi2axilite.sv', package='umi')

    dut.use(sumi)

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config',
            'utils/testbench/config.vlt',
            package='umi')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-Wall')

    # Settings - enable tracing
    dut.set('tool', 'verilator', 'task', 'compile', 'var', 'trace_type', 'fst')

    # Build simulator
    dut.run()

    return dut.find_result('vexe', step='compile')


def main(vldmode="2", rdymode="2", host2dut="host2dut_0.q", dut2host="dut2host_0.q"):
    # clean up old queues if present
    for q in [host2dut, dut2host]:
        delete_queue(q)

    verilator_bin = build_testbench()

    # launch the simulation
    ret_val = verilator_run(verilator_bin, plusargs=['trace', ('valid_mode', vldmode), ('ready_mode', rdymode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx(host2dut, dut2host)

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

    ret_val.wait()
    print("### TEST PASS ###")


if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('--rdymode', default='2')
    args = parser.parse_args()

    main(vldmode=args.vldmode,
         rdymode=args.rdymode)
