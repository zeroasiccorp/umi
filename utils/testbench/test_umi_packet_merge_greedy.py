#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC

import random
import time
import numpy as np
from pathlib import Path
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx, delete_queue, verilator_run, binary_run, random_umi_packet


def build_testbench(topo="2d"):
    dut = SbDut('testbench')

    EX_DIR = Path('../..')

    # Set up inputs
    if topo=='2d':
        dut.input('testbench_umi_packet_merge_greedy.v')
        print("### Running 2D topology ###")
    # elif topo=='3d':
    #     dut.input('testbench_3d.sv')
    #     dut.input('dut_ebrick_3d.v')
    #     print("### Running 3D topology ###")
    else:
        raise ValueError('Invalid topology')

    dut.input('testbench_umi_packet_merge_greedy.cc')
    for option in ['ydir', 'idir']:
        dut.add('option', option, EX_DIR / 'umi' / 'rtl')
        dut.add('option', option, EX_DIR / 'utils' / 'rtl')
        dut.add('option', option, EX_DIR / 'submodules' / 'lambdalib' / 'ramlib' / 'rtl')
        dut.add('option', option, EX_DIR / 'submodules' / 'lambdalib' / 'stdlib' / 'rtl')
        dut.add('option', option, EX_DIR / 'submodules' / 'lambdalib' / 'padring' / 'rtl')
        dut.add('option', option, EX_DIR / 'submodules' / 'lambdalib' / 'vectorlib' / 'rtl')

    # Verilator configuration
    vlt_config = EX_DIR / 'utils' / 'testbench' / 'config.vlt'
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', vlt_config)
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '--coverage')

    # Settings
    dut.set('option', 'trace', True)  # enable VCD (TODO: FST option)

    # Build simulator
    dut.run()

    return dut.find_result('vexe', step='compile')


def main(topo="2d", vldmode="2", n=100, client2rtl="client2rtl_0.q", rtl2client="rtl2client_0.q"):
    # clean up old queues if present
    delete_queue(client2rtl)
    delete_queue(rtl2client)

    verilator_bin = build_testbench(topo)

    # launch the simulation
    ret_val = verilator_run(verilator_bin, plusargs=['trace', ('valid_mode', vldmode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    umi = UmiTxRx(client2rtl, rtl2client)

    print("### Starting random test ###")

    n_sent = 0

    while (n_sent < n):
        txp = random_umi_packet()
        if umi.send(txp, blocking=False):
            print('* TX *')
            print(str(txp))
            n_sent += 1

    ret_val.wait()


if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--topo', default='2d')
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('-n', type=int, default=10, help='Number of'
                    ' transactions to send during the test.')
    args = parser.parse_args()

    main(topo=args.topo, vldmode=args.vldmode, n=args.n)
