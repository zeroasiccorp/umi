#!/usr/bin/env python3

# Copyright (C) 2025 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import numpy as np
from switchboard import SbDut, UmiTxRx
from umi import sumi

def main():
    # build the simulator
    dut = build_testbench()

    # launch the simulation
    dut.simulate(
        plusargs=[
            ('valid_mode', dut.args.vldmode),
            ('ready_mode', dut.args.rdymode)
        ]
    )

    # Switchboard queue initialization
    umi = UmiTxRx('host2dut_0.q', 'dut2host_0.q', fresh=True)

    np.set_printoptions(formatter={'int': hex})


    print("### Starting test ###")
    # regif accesses are all 32b wide and aligned

    umi.write(0, np.uint8(0xef))
    read_data = umi.read(0, 4)
    print(f'Read addr=0 data={read_data}')

    umi.write(0, np.uint16(0xbeef))
    read_data = umi.read(0, 4)
    print(f'Read addr=0 data={read_data}')

    umi.write(0, np.uint32(0xdeadbeef))
    read_data = umi.read(0, 4)
    print(f'Read addr=0 data={read_data}')

    umi.write(200, np.uint32(0xa0a0a0a0))
    read_data = umi.read(200, 4)
    print(f'Read addr=200 data={read_data}')

    read_data = umi.read(0, 4)
    print(f'Read addr=0 data={read_data}')

def build_testbench(fast=False):

    extra_args = {
        '--vldmode': dict(type=int, default=1, help='Valid mode'),
        '--rdymode': dict(type=int, default=1, help='Ready mode'),
    }

    # Create dut
    dut = SbDut('testbench', cmdline=True, extra_args=extra_args,
                trace=True, trace_type='vcd', default_main=True)

    # Set up inputs
    dut.use(sumi)
    dut.input('testbench.sv')

    # Verilator configuration
    dut.add('tool', 'verilator', 'task', 'compile', 'warningoff',
            ['WIDTHTRUNC', 'TIMESCALEMOD'])

    dut.build()

    return dut


if __name__ == '__main__':
    main()
