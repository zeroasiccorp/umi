#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import multiprocessing
from switchboard import UmiTxRx, delete_queue
from umi_common import umi_send


def test_demux(sumi_dut, random_seed, sb_umi_valid_mode, sb_umi_ready_mode):
    n = 4000 # Number of transactions to be sent to each demux input port
    in_ports = 1 # Number of input ports. Fixed to 1 for demux
    out_ports = 4 # Number of output ports. Must match testbench

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

    send_proc = multiprocessing.Process(target=umi_send,
                                        args=(0, n, out_ports, random_seed,))

    send_proc.start()

    recv_queue = [[] for i in range(out_ports)]
    send_queue = [[] for i in range(out_ports)]

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
                    recv_queue[i].append(rxp)
                    nrecv += 1

        for i in range(in_ports):
            txp = tee[i].recv(blocking=False)
            if txp is not None:
                if nsend >= in_ports*n:
                    raise Exception('Unexpected packet sent')
                else:
                    send_dst = (txp.dstaddr >> 40)
                    send_queue[send_dst].append(txp)
                    nsend += 1

    # join Tx sender
    send_proc.join()

    for i in range(out_ports):
        if len(send_queue[i]) != len(recv_queue[i]):
            print(f"packets sent: {len(send_queue[i])} packets received: {len(recv_queue[i])}")
        assert len(send_queue[i]) == len(recv_queue[i])
        for txp, rxp in zip(send_queue[i], recv_queue[i]):
            assert txp == rxp
        print(f"Received {len(recv_queue[i])} packets at port {i}")


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
