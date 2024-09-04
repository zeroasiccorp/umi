#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import multiprocessing
import numpy as np
from switchboard import UmiTxRx, random_umi_packet, delete_queue


def umi_send(umi_q, n, ports, seed):

    np.random.seed(seed)

    tee = [UmiTxRx(f'tee_{x}.q', '') for x in range(ports)]

    for count in range(n*ports):
        dstport = np.random.randint(0, ports)
        dstaddr = (2**8)*np.random.randint(0, 2**32) + (2**(40+dstport))
        srcaddr = (2**8)*np.random.randint(0, 2**32) + (2**(40+ports))
        txp = random_umi_packet(dstaddr=dstaddr, srcaddr=srcaddr)
        print(f"Sending #{count} cmd: 0x{txp.cmd:08x} srcaddr: 0x{srcaddr:08x} "
              f"dstaddr: 0x{dstaddr:08x} to port {dstport}")
        # send the packet to both simulation and local queues
        umi_q.send(txp)
        tee[dstport].send(txp)


def test_demux(sumi_dut, random_seed, sb_umi_valid_mode, sb_umi_ready_mode):
    n = 100
    ports = 4

    for x in range(ports):
        delete_queue(f'tee_{x}.q')

    # Instantiate TX and RX queues
    umi = UmiTxRx('client2rtl_0.q', '', fresh=True)
    recvq = [UmiTxRx('', f'rtl2client_{x}.q', fresh=True) for x in range(ports)]
    tee = [UmiTxRx('', f'tee_{x}.q') for x in range(ports)]

    # launch the simulation
    sumi_dut.simulate(
            plusargs=[('valid_mode', sb_umi_valid_mode),
                      ('ready_mode', sb_umi_ready_mode)])

    print("### Starting test ###")

    send_proc = multiprocessing.Process(target=umi_send,
                                        args=(umi, n, ports, random_seed,))

    send_proc.start()

    recv_queue = [[] for i in range(ports)]
    send_queue = [[] for i in range(ports)]

    nrecv = 0
    nsend = 0
    while (nrecv < ports*n) or (nsend < ports*n):
        for i in range(ports):
            rxp = recvq[i].recv(blocking=False)
            if rxp is not None:
                if nrecv >= ports*n:
                    print(f'Unexpected packet received {nrecv}')
                    raise Exception(f'Unexpected packet received {nrecv}')
                else:
                    recv_src = (rxp.srcaddr >> 40)
                    print(f"port {i} receiving srcaddr: 0x{rxp.srcaddr:08x} "
                          f"dstaddr: 0x{rxp.dstaddr:08x} src: {recv_src} #{nrecv}")
                    recv_queue[i].append(rxp)
                    nrecv += 1

        for i in range(ports):
            txp = tee[i].recv(blocking=False)
            if txp is not None:
                if nsend >= ports*n:
                    raise Exception('Unexpected packet sent')
                else:
                    send_queue[i].append(txp)
                    nsend += 1

    # join Tx sender
    send_proc.join()

    for i in range(ports):
        if len(send_queue[i]) != len(recv_queue[i]):
            print(f"packets sent: {len(send_queue[i])} packets received: {len(recv_queue[i])}")
        assert len(send_queue[i]) == len(recv_queue[i])
        for txp, rxp in zip(send_queue[i], recv_queue[i]):
            assert txp == rxp
        print(f"Received {len(recv_queue[i])} packets at port {i}")


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
