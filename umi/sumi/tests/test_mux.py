#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import multiprocessing
from switchboard import UmiTxRx, delete_queue
from umi_common import umi_send


def test_mux(sumi_dut, random_seed, sb_umi_valid_mode, sb_umi_ready_mode):
    n = 1000 # Number of transactions to be sent to each mux input port
    in_ports = 4 # Number of input ports. Must match testbench
    out_ports = 1 # Number of output ports. Fixed to 1 for mux

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

    send_procs = []

    for x in range(in_ports):
        send_procs.append(multiprocessing.Process(target=umi_send,
                                                  args=(x, n, out_ports, (random_seed+x),)))

    for proc in send_procs:
        proc.start()

    recv_queue = [[] for i in range(in_ports)]
    send_queue = [[] for i in range(in_ports)]

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
                    recv_queue[recv_src].append(rxp)
                    nrecv += 1

        for i in range(in_ports):
            txp = tee[i].recv(blocking=False)
            if txp is not None:
                if nsend >= in_ports*n:
                    raise Exception('Unexpected packet sent')
                else:
                    send_queue[i].append(txp)
                    nsend += 1

    # join Tx senders
    for proc in send_procs:
        proc.join()

    for i in range(in_ports):
        if len(send_queue[i]) != len(recv_queue[i]):
            print(f"packets sent: {len(send_queue[i])} packets received: {len(recv_queue[i])}")
        assert len(send_queue[i]) == len(recv_queue[i])
        for txp, rxp in zip(send_queue[i], recv_queue[i]):
            assert txp == rxp
        print(f"Received {len(recv_queue[i])} packets at port {i}")


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
