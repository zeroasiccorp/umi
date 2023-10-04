#!/usr/bin/env python3

# Example illustrating how UMI packets handled in the Switchboard Python binding
# Copyright (C) 2023 Zero ASIC

import random
import numpy as np
from pathlib import Path
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx, delete_queue, verilator_run, binary_run

THIS_DIR = Path(__file__).resolve().parent


def build_testbench():
    dut = SbDut('testbench')

    EX_DIR = Path('..')
    EX_DIR = EX_DIR.resolve()

    # Set up inputs
    dut.input('testbench_mem_agent.sv')

    dut.input(EX_DIR / '..' / 'submodules' / 'switchboard' / 'examples' / 'common' / 'verilator' / 'testbench.cc')
    for option in ['ydir', 'idir']:
        dut.add('option', option, EX_DIR / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'switchboard' / 'examples' / 'common' / 'verilog')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'ramlib' / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'stdlib' / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'vectorlib' / 'rtl')

    # Verilator configuration
    vlt_config = EX_DIR / 'testbench' / 'config.vlt'
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', vlt_config)
#    dut.set('option', 'relax', True)
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '--prof-cfuncs')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-CFLAGS')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '-DVL_DEBUG')

    # Settings
    dut.set('option', 'trace', True)  # enable VCD (TODO: FST option)

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
        if (origdata & (maxrange>>1)):
            origdata = int(origdata) - int(maxrange)
        else:
            origdata = int(origdata)
        if (atomicdata & (maxrange>>1)):
            atomicdata = int(atomicdata) - int(maxrange)
        else:
            atomicdata = int(atomicdata)
        tempval = origdata if (origdata > atomicdata) else atomicdata
    elif (operation == 5):
        if (origdata & (maxrange>>1)):
            origdata = int(origdata) - int(maxrange)
        else:
            origdata = int(origdata)
        if (atomicdata & (maxrange>>1)):
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
    #verilator_run(verilator_bin, plusargs=['trace'])
    verilator_run(verilator_bin, plusargs=['trace', ('valid_mode', vldmode), ('ready_mode', rdymode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx(host2dut, dut2host)

    print("### Statring test ###")

    avail_datatype = [np.uint8, np.uint16, np.uint32]

    # un-aligned accesses
    for count in range (n):
        addr = np.random.randint(0, 512)
        src_addr = random.randrange(2**64-1)
        # lenth should not cross the DW boundary - umi_mem_agent limitation
        length = np.random.randint(0, 256)
        wordindexer = np.random.choice([0,1,2])
        maxrange = 2**(8*(2**wordindexer))
        data = np.random.randint(0, maxrange, size=(length+1), dtype=avail_datatype[wordindexer])
        addr = addr*(2**wordindexer) & 0x1FF

        print(f"umi writing {length+1} words of type {avail_datatype[wordindexer]} to addr 0x{addr:08x}")
        host.write(addr, data)
        atomicopcode = np.random.randint(0, 9)
        atomicdata = np.random.randint(0,256,dtype=avail_datatype[wordindexer])
        print(f"umi atomic opcode: {atomicopcode} of type {avail_datatype[wordindexer]} to addr 0x{addr:08x}")
        atomicval = host.atomic(addr, atomicdata, atomicopcode)
        if not (atomicval == data[0]):
            print(f"ERROR umi atomic from addr 0x{addr:08x} expected {data[0]} actual {atomicval}")
            assert (atomicval == data[0])
        data[0] = apply_atomic(data[0], atomicdata, atomicopcode, maxrange)

        print(f"umi read from addr 0x{addr:08x}")
        val = host.read(addr, length+1, dtype=avail_datatype[wordindexer])
        if not (np.array_equal(val, data)):
            print(f"ERROR umi read from addr 0x{addr:08x} expected {data} actual {val}")
            assert (np.array_equal(val, data))

    print("### TEST PASS ###")

if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('--rdymode', default='2')
    parser.add_argument('-n', type=int, default=10, help='Number of'
                    ' transactions to send during the test.')
    args = parser.parse_args()

    main(vldmode=args.vldmode,rdymode=args.rdymode, n=args.n)
