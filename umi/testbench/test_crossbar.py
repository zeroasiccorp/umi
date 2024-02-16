#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import multiprocessing
import random
import numpy as np
from pathlib import Path
from argparse import ArgumentParser
from switchboard import (UmiTxRx, random_umi_packet, delete_queue,
    verilator_run, SbDut, UmiCmd, umi_opcode)

THIS_DIR = Path(__file__).resolve().parent

def build_testbench():
    dut = SbDut('testbench', default_main=True)

    EX_DIR = Path('..')
    EX_DIR = EX_DIR.resolve()

    # Set up inputs
    dut.input('testbench_crossbar.sv')

    for option in ['ydir', 'idir']:
        dut.add('option', option, EX_DIR / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'lambdalib' / 'ramlib' / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'lambdalib' / 'stdlib' / 'rtl')
        dut.add('option', option, EX_DIR / '..' / 'submodules' / 'lambdalib' / 'lambdalib' / 'vectorlib' / 'rtl')

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

def umi_send(x,n,ports):
    import os

    random.seed(os.getpid())
    np.random.seed(os.getpid())

    umi = UmiTxRx(f'client2rtl_{x}.q', '')
    tee = UmiTxRx(f'tee_{x}.q', '')

    for count in range (n):
        dstport = random.randint(0,ports-1)
        dstaddr = (2**8)*random.randint(0,(2**32)-1) + dstport*(2**40)
        srcaddr = (2**8)*random.randint(0,(2**32)-1) + x*(2**40)
        txp = random_umi_packet(dstaddr=dstaddr,srcaddr=srcaddr)
        print(f"port {x} sending #{count} cmd: 0x{txp.cmd:08x} srcaddr: 0x{srcaddr:08x} dstaddr: 0x{dstaddr:08x} to port {dstport}")
        # send the packet to both simulation and local queues
        umi.send(txp)
        tee.send(txp)

def main(vldmode="2", rdymode="2", n=100, ports=4):
    for x in range (ports):
        delete_queue(f'rtl2client_{x}.q')
        delete_queue(f'client2rtl_{x}.q')
        delete_queue(f'tee_{x}.q')

    verilator_bin = build_testbench()

    # launch the simulation
    verilator_run(verilator_bin, plusargs=['trace', ('PORTS', ports), ('valid_mode', vldmode), ('ready_mode', rdymode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    umi = [UmiTxRx('', f'rtl2client_{x}.q') for x in range(ports)]
    tee = [UmiTxRx('', f'tee_{x}.q') for x in range(ports)]

    print("### Starting test ###")
    recv_queue = [[[] for i in range(n)] for j in range(ports)]
    send_queue = [[[] for i in range(n)] for j in range(ports)]

    procs = []
    for x in range(ports):
        procs.append(multiprocessing.Process(target=umi_send, args=(x,n,ports,)))

    for proc in procs:
        proc.start()

    nrecv = 0
    nsend = 0
    while (nrecv < ports*n) or (nsend < ports*n):
        for i in range(ports):
            rxp = umi[i].recv(blocking=False)
            if rxp is not None:
                if nrecv >= ports*n:
                    print(f'Unexpected packet received {nrecv}')
                    raise Exception(f'Unexpected packet received {nrecv}')
                else:
                    recv_src = (rxp.srcaddr >> 40)
                    print(f"port {i} receiving srcaddr: 0x{rxp.srcaddr:08x} dstaddr: 0x{rxp.dstaddr:08x} src: {recv_src} #{nrecv}")
                    recv_queue[recv_src][i].append(rxp)
                    nrecv += 1

        for i in range(ports):
            txp = tee[i].recv(blocking=False)
            if txp is not None:
                if nsend >= ports*n:
                    raise Exception('Unexpected packet sent')
                else:
                    send_dst = (txp.dstaddr >> 40)
                    #print(f"Tee port {i} dst: {send_dst} #{nsend}")
                    send_queue[i][send_dst].append(txp)
                    nsend += 1

    # join running processes

    for proc in procs:
        proc.join()

    for i in range(ports):
        for j in range(ports):
            if len(send_queue[i][j]) != len(recv_queue[i][j]):
                print(f"packets sent: {len(send_queue[i][j])} packets received: {len(recv_queue[i][j])}")
            assert len(send_queue[i][j]) == len(recv_queue[i][j])
            for txp, rxp in zip(send_queue[i][j],recv_queue[i][j]):
                #print(f"{rxp} {txp}")
                assert txp == rxp
            print(f"compared {len(recv_queue[i][j])} packets from port {i} to port {j}")
    print("TEST PASS")

if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--vldmode', default='2')
    parser.add_argument('--rdymode', default='2')
    parser.add_argument('-n', type=int, default=10, help='Number of'
                    ' transactions to send during the test.')
    parser.add_argument('-ports', type=int, default=4, help='Number of ports')
    args = parser.parse_args()

    main(vldmode=args.vldmode,rdymode=args.rdymode, n=args.n, ports=args.ports)
