#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import multiprocessing
import random
import numpy as np
from switchboard import UmiTxRx, random_umi_packet, delete_queue
from umi import sumi


def umi_send(x, n, ports):
    import os

    random.seed(os.getpid())
    np.random.seed(os.getpid())

    umi = UmiTxRx(f'client2rtl_{x}.q', '')
    tee = UmiTxRx(f'tee_{x}.q', '')

    for count in range(n):
        dstport = random.randint(0, ports-1)
        dstaddr = (2**8)*random.randint(0, (2**32)-1) + dstport*(2**40)
        srcaddr = (2**8)*random.randint(0, (2**32)-1) + x*(2**40)
        txp = random_umi_packet(dstaddr=dstaddr, srcaddr=srcaddr)
        print(f"port {x} sending #{count} cmd: 0x{txp.cmd:08x} srcaddr: 0x{srcaddr:08x} "
              f"dstaddr: 0x{dstaddr:08x} to port {dstport}")
        # send the packet to both simulation and local queues
        umi.send(txp)
        tee.send(txp)


@pytest.mark.skip(reason="Crossbar asserts output valid even when in reset")
def test_crossbar(sumi_dut, valid_mode, ready_mode):
    n = 100
    ports = 4
    for x in range(ports):
        delete_queue(f'rtl2client_{x}.q')
        delete_queue(f'client2rtl_{x}.q')
        delete_queue(f'tee_{x}.q')

    # launch the simulation
    sumi_dut.simulate(
            plusargs=['trace', ('PORTS', ports),
                      ('valid_mode', valid_mode),
                      ('ready_mode', ready_mode)])

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
        procs.append(multiprocessing.Process(target=umi_send, args=(x, n, ports,)))

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
                    print(f"port {i} receiving srcaddr: 0x{rxp.srcaddr:08x} "
                          f"dstaddr: 0x{rxp.dstaddr:08x} src: {recv_src} #{nrecv}")
                    recv_queue[recv_src][i].append(rxp)
                    nrecv += 1

        for i in range(ports):
            txp = tee[i].recv(blocking=False)
            if txp is not None:
                if nsend >= ports*n:
                    raise Exception('Unexpected packet sent')
                else:
                    send_dst = (txp.dstaddr >> 40)
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
            for txp, rxp in zip(send_queue[i][j], recv_queue[i][j]):
                assert txp == rxp
            print(f"compared {len(recv_queue[i][j])} packets from port {i} to port {j}")


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])