#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import multiprocessing
from switchboard import UmiTxRx, delete_queue
from umi_common import umi_send


def test_switch(sumi_dut, random_seed, sb_umi_valid_mode, sb_umi_ready_mode):
    n = 1000 # Number of transactions to be sent to each switch input port
    in_ports = 4 # Number of input ports. Must match testbench
    out_ports = 2 # Number of output ports. Must match testbench

    for x in range(in_ports):
        delete_queue(f'client2rtl_{x}.q')
        delete_queue(f'tee_{x}.q')

    # Instantiate TX and RX queues
    umi = [UmiTxRx('', f'rtl2client_{x}.q', fresh=True) for x in range(out_ports)]
    tee = [UmiTxRx('', f'tee_{x}.q') for x in range(in_ports)]

    # launch the simulation
    sumi_dut.simulate(
            plusargs=[('valid_mode', sb_umi_valid_mode),
                      ('ready_mode', sb_umi_ready_mode)])

    print("### Starting test ###")

    procs = []
    for x in range(in_ports):
        procs.append(multiprocessing.Process(target=umi_send,
                                             args=(x, n, out_ports, (random_seed+x),)))

    for proc in procs:
        proc.start()

    recv_queue = [[[] for i in range(out_ports)] for j in range(in_ports)]
    send_queue = [[[] for i in range(out_ports)] for j in range(in_ports)]

    nrecv = 0
    nsend = 0
    while (nrecv < in_ports*n) or (nsend < in_ports*n):
        for i in range(out_ports):
            rxp = umi[i].recv(blocking=False)
            if rxp is not None:
                if nrecv >= in_ports*n:
                    print(f'Unexpected packet received {nrecv}')
                    raise Exception(f'Unexpected packet received {nrecv}')
                else:
                    recv_src = (rxp.srcaddr >> 40)
                    print(f"port {i} receiving srcaddr: 0x{rxp.srcaddr:08x} "
                          f"dstaddr: 0x{rxp.dstaddr:08x} src: {recv_src} #{nrecv}")
                    recv_queue[recv_src][i].append(rxp)
                    nrecv += 1

        for i in range(in_ports):
            txp = tee[i].recv(blocking=False)
            if txp is not None:
                if nsend >= in_ports*n:
                    raise Exception('Unexpected packet sent')
                else:
                    send_dst = (txp.dstaddr >> 40)
                    send_queue[i][send_dst].append(txp)
                    nsend += 1

    # join running processes
    for proc in procs:
        proc.join()

    for i in range(in_ports):
        for j in range(out_ports):
            if len(send_queue[i][j]) != len(recv_queue[i][j]):
                print(f"packets sent: {len(send_queue[i][j])} packets received: {len(recv_queue[i][j])}")
            assert len(send_queue[i][j]) == len(recv_queue[i][j])
            for txp, rxp in zip(send_queue[i][j], recv_queue[i][j]):
                assert txp == rxp
            print(f"compared {len(recv_queue[i][j])} packets from port {i} to port {j}")


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
