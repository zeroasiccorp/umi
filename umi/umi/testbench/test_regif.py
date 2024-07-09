#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import random
import numpy as np
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx, delete_queue, verilator_run
import umi


def build_testbench():
    dut = SbDut('testbench', default_main=True)

    # Set up inputs
    dut.input('umi/testbench/testbench_regif.sv', package='umi')

    dut.use(umi)
    dut.add('option', 'library', 'umi')
    dut.add('option', 'library', 'lambdalib_ramlib')

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', 'umi/testbench/config.vlt', package='umi')
#    dut.set('option', 'relax', True)
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '--prof-cfuncs')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-CFLAGS')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-DVL_DEBUG')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-Wall')

    # Settings - enable tracing
    dut.set('option', 'trace', False)
    dut.set('tool', 'verilator', 'task', 'compile', 'var', 'trace_type', 'fst')

    # Build simulator
    dut.run()

    return dut.find_result('vexe', step='compile')


def apply_atomic(origdata, atomicdata, operation, maxrange):
    tempval = origdata
    if (operation == 0):
        tempval = origdata + atomicdata
        if (tempval >= maxrange):
            tempval = tempval - maxrange
    elif (operation == 1):
        tempval = origdata & atomicdata
    elif (operation == 2):
        tempval = origdata | atomicdata
    elif (operation == 3):
        tempval = origdata ^ atomicdata
    elif (operation == 4):
        if (origdata & (maxrange >> 1)):
            origdata = int(origdata) - int(maxrange)
        else:
            origdata = int(origdata)
        if (atomicdata & (maxrange >> 1)):
            atomicdata = int(atomicdata) - int(maxrange)
        else:
            atomicdata = int(atomicdata)
        tempval = origdata if (origdata > atomicdata) else atomicdata
    elif (operation == 5):
        if (origdata & (maxrange >> 1)):
            origdata = int(origdata) - int(maxrange)
        else:
            origdata = int(origdata)
        if (atomicdata & (maxrange >> 1)):
            atomicdata = int(atomicdata) - int(maxrange)
        else:
            atomicdata = int(atomicdata)
        tempval = atomicdata if (origdata > atomicdata) else origdata
    elif (operation == 6):
        tempval = origdata if (origdata > atomicdata) else atomicdata
    elif (operation == 7):
        tempval = atomicdata if (origdata > atomicdata) else origdata
    elif (operation == 8):
        tempval = atomicdata
    else:
        tempval = atomicdata

    return tempval


def main(vldmode="2", rdymode="2", n=100, host2dut="host2dut_0.q", dut2host="dut2host_0.q"):
    # clean up old queues if present
    for q in [host2dut, dut2host]:
        delete_queue(q)

    verilator_bin = build_testbench()

    # launch the simulation
    verilator_run(verilator_bin, plusargs=['trace', ('valid_mode', vldmode), ('ready_mode', rdymode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx(host2dut, dut2host)

    print("### Starting test ###")

    # regif accesses are all 32b wide and aligned
    for _ in range(n):
        addr = np.random.randint(0, 512) * 4
        # length should not cross the DW boundary - umi_mem_agent limitation
        data = np.uint32(random.randrange(2**32-1))

        print(f"umi writing 0x{data:08x} to addr 0x{addr:08x}")
        host.write(addr, data)
        atomicopcode = np.random.randint(0, 9)
        atomicdata = np.uint32(random.randrange(2**32-1))
        print(f"umi atomic opcode: {atomicopcode} data: {atomicdata:08x} to addr 0x{addr:08x}")
        atomicval = host.atomic(addr, atomicdata, atomicopcode)
        if not (atomicval == data):
            print(f"ERROR umi atomic from addr 0x{addr:08x} expected {data} actual {atomicval}")
            assert (atomicval == data)
        data = np.uint32(apply_atomic(data, atomicdata, atomicopcode, 2**32))

        print(f"umi read from addr 0x{addr:08x}")
        val = host.read(addr, np.uint32)
        if not (val == data):
            print(f"ERROR umi read from addr 0x{addr:08x} expected {data} actual {val}")
            assert (val == data)

    print("### TEST PASS ###")


if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('--rdymode', default='2')
    parser.add_argument('-n', type=int, default=10,
                        help='Number of transactions to send during the test.')
    args = parser.parse_args()

    main(vldmode=args.vldmode,
         rdymode=args.rdymode,
         n=args.n)
