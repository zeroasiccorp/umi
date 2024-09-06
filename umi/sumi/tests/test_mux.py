#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
import multiprocessing
from switchboard import UmiTxRx, random_umi_packet, delete_queue


def test_mux(sumi_dut, umi_send, sb_umi_valid_mode, sb_umi_ready_mode):
    n = 1000  # Number of transactions to be sent to each mux input port
    in_ports = 4  # Number of input ports. Must match testbench
    out_ports = 1  # Number of output ports. Fixed to 1 for mux

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
                                                  args=(x, n, out_ports,)))

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


@pytest.mark.skip(reason="Must only be run when evaluating performance using waveforms")
def test_round_robin_arb(sumi_dut):
    '''
    This test is used to get an initial idea of the performance impact of
    the arbitration scheme present in the mux. With the thermometer based
    round robin scheme this test shows a performance penalty of up to 4
    cycles for a thermometer masked transaction. This test must be run with
    the waveform enabled.
    '''

    # Instantiate TX and RX queues
    inq = [UmiTxRx(f'client2rtl_{x}.q', '', fresh=True) for x in range(2)]

    # launch the simulation
    sumi_dut.simulate(
            plusargs=[('valid_mode', 1),
                      ('ready_mode', 1)])

    txp = random_umi_packet()
    print(f"Sending cmd: 0x{txp.cmd:08x} "
          f"srcaddr: 0x{txp.srcaddr:08x} dstaddr: 0x{txp.dstaddr:08x}")
    # send the packet to both simulation and local queues
    inq[0].send(txp)
    inq[1].send(txp)
    inq[0].send(txp)


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
