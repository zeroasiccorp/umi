#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import random
import numpy as np
from switchboard import SbDut, UmiTxRx, verilator_run
from umi import sumi


def build_testbench(dut):
    # Set up inputs
    dut.input('utils/testbench/testbench_umi2apb.sv', package='umi')

    dut.use(sumi)

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', 'utils/testbench/config.vlt',
            package='umi')
#    dut.set('option', 'relax', True)
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '--prof-cfuncs')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-CFLAGS')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-DVL_DEBUG')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-Wall')

    # Settings - enable tracing
    dut.set('tool', 'verilator', 'task', 'compile', 'var', 'trace', True)
    dut.set('tool', 'verilator', 'task', 'compile', 'var', 'trace_type', 'fst')

    # Build simulator
    dut.run()

    return dut.find_result('vexe', step='compile')


def main(host2dut="host2dut_0.q", dut2host="dut2host_0.q"):

    extra_args = {
        '--vldmode': dict(type=int, default=1, help='Valid mode'),
        '--rdymode': dict(type=int, default=1, help='Ready mode'),
        '-n': dict(type=int, default=10, help='Number of transactions'
                   'to send during the test.')
    }

    dut = SbDut('testbench', cmdline=True, extra_args=extra_args, trace=True, default_main=True)

    verilator_bin = build_testbench(dut)

    # launch the simulation
    verilator_run(verilator_bin)

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx(host2dut, dut2host, fresh=True)

    print("### Starting test ###")

    # regif accesses are all 32b wide and aligned
    for _ in range(dut.args.n):
        addr = np.random.randint(0, 512) * 4
        # length should not cross the DW boundary - umi_mem_agent limitation
        data = np.uint32(random.randrange(2**32-1))

        print(f"umi writing 0x{data:08x} to addr 0x{addr:08x}")
        host.write(addr, data)

        print(f"umi read from addr 0x{addr:08x}")
        val = host.read(addr, np.uint32)
        if not (val == data):
            print(f"ERROR umi read from addr 0x{addr:08x} expected {data} actual {val}")
            assert (val == data)

    print("### TEST PASS ###")


if __name__ == '__main__':
    main()
