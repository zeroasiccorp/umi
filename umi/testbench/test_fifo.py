#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import random
import numpy as np
from pathlib import Path
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx, delete_queue, verilator_run, binary_run, random_umi_packet

THIS_DIR = Path(__file__).resolve().parent


def build_testbench():
    dut = SbDut('testbench')

    EX_DIR = Path('..')
    EX_DIR = EX_DIR.resolve()

    # Set up inputs
    dut.input('testbench_fifo.sv')

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

    # Settings - enable tracing
    dut.set('option', 'trace', True)
    dut.set('tool', 'verilator', 'task', 'compile', 'var', 'trace_type', 'fst')

    # Build simulator
    dut.run()

    return dut.find_result('vexe', step='compile')


def main(vldmode="2", rdymode="2", host2dut="host2dut_0.q", dut2host="dut2host_0.q",split="0"):
    # clean up old queues if present
    for q in [host2dut, dut2host]:
        delete_queue(q)

    verilator_bin = build_testbench()

    # launch the simulation
    #verilator_run(verilator_bin, plusargs=['trace'])
    ret_val = verilator_run(verilator_bin, plusargs=['trace', ('valid_mode', vldmode), ('ready_mode', rdymode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx(host2dut, dut2host)

    print("### Statring test ###")

    for count in range (100):
        # length should not cross the DW boundary - umi_mem_agent limitation
        length = np.random.randint(0,15)
        dst_addr = 32*random.randrange(2**(10-5)-1) # sb limitation - should align to bus width
        src_addr = 32*random.randrange(2**(10-5)-1)
        data8 = np.random.randint(0,255,size=length,dtype=np.uint8)
        print(f"umi writing {length+1} bytes to addr 0x{dst_addr:08x}")
        host.write(dst_addr, data8, srcaddr=src_addr)
        print(f"umi read from addr 0x{dst_addr:08x}")
        val8 = host.read(dst_addr, length, np.uint8, srcaddr=src_addr)
        if ~((val8 == data8).all()):
            print(f"ERROR umi read from addr 0x{dst_addr:08x}")
            print(f"Expected:")
            print(f"{data8}")
            print(f"Actual:")
            print(f"{val8}")
            assert (val8 == data8).all()

    ret_val.wait()
    print("### TEST PASS ###")

if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('--rdymode', default='2')
    parser.add_argument('--split', default='0')
    args = parser.parse_args()

    main(vldmode=args.vldmode,rdymode=args.rdymode,split=args.split)
