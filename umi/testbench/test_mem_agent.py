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


def main(vldmode="2", rdymode="2", host2dut="host2dut_0.q", dut2host="dut2host_0.q"):
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

    for count in range (1000):
        addr = random.randrange(511)
        src_addr = random.randrange(2**64-1)
        # lenth should not cross the DW boundary - umi_mem_agent limitation
        length = np.random.randint(0,16-addr%16)
        data8 = np.random.randint(0,255,size=length,dtype=np.uint8)
        print(f"umi writing {length+1} bytes to addr 0x{addr:08x}")
        host.write(addr, data8, srcaddr=src_addr)
        print(f"umi read from addr 0x{addr:08x}")
        val8 = host.read(addr, length, np.uint8, srcaddr=src_addr)
        if ~((val8 == data8).all()):
            print(f"ERROR umi read from addr 0x{addr:08x} expected {data8} actual {val8}")
            assert (val8 == data8).all()

    print("### TEST PASS ###")

if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('--rdymode', default='2')
    args = parser.parse_args()

    main(vldmode=args.vldmode,rdymode=args.rdymode)
