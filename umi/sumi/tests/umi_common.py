#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import numpy as np
from switchboard import UmiTxRx, random_umi_packet


def umi_send(host_num, num_packets_to_send, num_out_ports, seed):

    np.random.seed(seed)

    umi = UmiTxRx(f'client2rtl_{host_num}.q', '')
    tee = UmiTxRx(f'tee_{host_num}.q', '')

    for count in range(num_packets_to_send):
        dstport = np.random.randint(num_out_ports)
        dstaddr = (2**8)*np.random.randint(2**32) + dstport*(2**40)
        srcaddr = (2**8)*np.random.randint(2**32) + host_num*(2**40)
        txp = random_umi_packet(dstaddr=dstaddr, srcaddr=srcaddr)
        print(f"port {host_num} sending #{count} cmd: 0x{txp.cmd:08x} srcaddr: 0x{srcaddr:08x} "
              f"dstaddr: 0x{dstaddr:08x} to port {dstport}")
        # send the packet to both simulation and local queues
        umi.send(txp)
        tee.send(txp)
