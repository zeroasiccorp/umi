#!/usr/bin/env python3

# Example illustrating how to interact with the umi_fifo module

# Copyright (c) 2024 Zero ASIC Corporation
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import sys
import random
import numpy as np

from math import ceil, log2
from argparse import ArgumentParser
from switchboard import SbDut, AxiTxRx
import umi


def build_testbench(fast=False, tool='verilator'):
    dut = SbDut(tool=tool, default_main=True)

    dut.register_package_source(
        'verilog-axi',
        'git+https://github.com/alexforencich/verilog-axi.git',
        '38915fb'
    )

    # Set up inputs
    dut.input('utils/testbench/testbench_axi2umi.sv', package='umi')

    dut.add('tool', 'verilator', 'task', 'compile', 'warningoff', 'WIDTHEXPAND')
    dut.add('tool', 'verilator', 'task', 'compile', 'warningoff', 'CASEINCOMPLETE')
    dut.add('tool', 'verilator', 'task', 'compile', 'warningoff', 'WIDTHTRUNC')
    dut.add('tool', 'verilator', 'task', 'compile', 'warningoff', 'TIMESCALEMOD')

    dut.use(umi)
    dut.add('option', 'library', 'umi')
    dut.add('option', 'library', 'lambdalib_ramlib')
    dut.add('option', 'library', 'lambdalib_stdlib')
    dut.add('option', 'library', 'lambdalib_vectorlib')

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config',
            'utils/testbench/config.vlt',
            package='umi')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-Wall')

    # Settings - enable tracing
    dut.set('option', 'trace', True)
    dut.set('tool', 'verilator', 'task', 'compile', 'var', 'trace_type', 'fst')

    dut.build(fast=fast)

    return dut


def main(n=100, fast=False, tool='verilator', max_bytes=10, max_beats=256):
    # build the simulator
    dut = build_testbench(fast=fast, tool=tool)

    # create the queues
    axi = AxiTxRx('axi', data_width=64, addr_width=64, id_width=8, max_beats=max_beats)

    # launch the simulation
    dut.simulate()

    # run the test: write to random addresses and read back
    # Valid address width is based on memory model in testbench_axi2umi.sv
    valid_addr_width = 15 #axi.addr_width

    success = True

    for _ in range(n):
        addr = random.randint(0, (1 << valid_addr_width) - 1)
        size = random.randint(1, min(max_bytes, (1 << valid_addr_width) - addr))

        #########
        # write #
        #########

        data = np.random.randint(0, 255, size=size, dtype=np.uint8)

        # perform the write
        axi.write(addr, data)
        print(f'Wrote addr=0x{addr:x} data={data}')

        ########
        # read #
        ########

        # perform the read
        read_data = axi.read(addr, size)
        print(f'Read addr=0x{addr:x} data={read_data}')

        # check against the write
        if not np.array_equal(data, read_data):
            print('MISMATCH')
            success = False

    if success:
        print("PASS!")
        sys.exit(0)
    else:
        print("FAIL")
        sys.exit(1)


if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('-n', type=int, default=100, help='Number of'
        ' words to write as part of the test.')
    parser.add_argument('--max-bytes', type=int, default=10, help='Maximum'
        ' number of bytes in any single read/write.')
    parser.add_argument('--max-beats', type=int, default=256, help='Maximum'
        ' number of beats to use in AXI transfers.')
    parser.add_argument('--fast', action='store_true', help='Do not build'
        ' the simulator binary if it has already been built.')
    parser.add_argument('--tool', default='verilator', choices=['icarus', 'verilator'],
        help='Name of the simulator to use.')
    args = parser.parse_args()

    main(n=args.n, fast=args.fast, tool=args.tool, max_bytes=args.max_bytes)
