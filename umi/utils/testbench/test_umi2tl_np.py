#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC

import random
import numpy as np
from pathlib import Path
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx
from siliconcompiler.package import path as sc_path
from umi import sumi


def main():

    extra_args = {
        '--vldmode': dict(type=int, default=1, help='Valid mode'),
        '-n': dict(type=int, default=10, help='Number of transactions'
                   'to send during the test.')
    }

    dut = SbDut('testbench', cmdline=True, extra_args=extra_args,
                trace=False, trace_type='fst', default_main=False)

    # Set up inputs
    dut.input('utils/testbench/testbench_umi2tl_np.v', package='umi')
    dut.input('utils/testbench/testbench_umi2tl_np.cc', package='umi')
    dut.input('utils/testbench/tlmemsim.cpp', package='umi')

    dut.use(sumi)

    # Verilator configuration
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '--coverage')
    header_files_dir = Path(sc_path(dut, 'umi')) / 'utils' / 'testbench'
    dut.set('tool', 'verilator', 'task', 'compile', 'var', 'cflags', f'-I{header_files_dir}')
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', 'utils/testbench/config.vlt', package='umi')

    # Build simulator
    dut.build()

    # launch the simulation
    dut.simulate(plusargs=[('valid_mode', dut.args.vldmode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    umi = UmiTxRx("client2rtl_0.q", "rtl2client_0.q", fresh=True)

    print("### Starting random test ###")

    n_sent = 0

    while (n_sent < dut.args.n):
        print(f"Transaction {n_sent}:")
        addr = random.randrange(511)
        length = random.choice([1, 2, 4, 8])

        # FIXME: Align address. Limitation of umi2tl converter. Will be fixed in the next release
        addr = addr & (0xFFFFFFF8 | (8-length))

        data8 = np.random.randint(0, 255, size=length, dtype=np.uint8)
        print(f"umi writing {length} bytes:: data: {data8} to addr: 0x{addr:08x}")
        umi.write(addr, data8, srcaddr=0x0000110000000000)
        print(f"umi reading {length} bytes:: from addr 0x{addr:08x}")
        val8 = umi.read(addr, length, np.uint8, srcaddr=0x0000110000000000)
        print(f"umi Read: {val8}")
        if not (val8 == data8).all():
            print(f"ERROR core read from addr 0x{addr:08x} expected {data8} actual {val8}")
        assert (val8 == data8).all()
        n_sent = n_sent + 1


if __name__ == '__main__':
    main()
