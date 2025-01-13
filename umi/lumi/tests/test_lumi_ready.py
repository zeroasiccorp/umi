#!/usr/bin/env python3

# Copyright (C) 2025 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import multiprocessing
import numpy as np
from switchboard import SbDut, UmiTxRx, UmiCmd, random_umi_packet, umi_loopback
from umi import lumi


def gen_mergeable_umi_packets(num_bytes, size, opcode_arr, bytes_per_tx=16):

    packets = []

    if (bytes_per_tx > 16):
        num_mergeable_packets = bytes_per_tx // 16
        # num_mergeable_packets = 256 // 16
    else:
        num_mergeable_packets = 1
        # num_mergeable_packets = 256 // bytes_per_tx

    for _ in range(num_bytes // bytes_per_tx):
    # for _ in range(num_bytes // 256):
        dstaddr = (2**8)*np.random.randint(2**32)
        srcaddr = (2**8)*np.random.randint(2**32)
        opcode = np.random.choice(opcode_arr)
        for _ in range(num_mergeable_packets):
            length = ((bytes_per_tx // num_mergeable_packets) >> size) - 1
            # length = ((256 // num_mergeable_packets) >> size) - 1
            txp = random_umi_packet(opcode=opcode, dstaddr=dstaddr,
                                    srcaddr=srcaddr, size=size, len=length,
                                    eom=0, eof=0, max_bytes=16)
            packets.append(txp)
            cmd_len = (txp.cmd >> 8) & 0xFF
            cmd_size = (txp.cmd >> 5) & 0x07
            cmd_bytes = (2**cmd_size) * (cmd_len + 1)
            dstaddr = dstaddr + cmd_bytes
            srcaddr = srcaddr + cmd_bytes

    return packets


def main():

    multiprocessing.set_start_method('fork')

    dut = SbDut('testbench', default_main=True, trace=True)

    dut.use(lumi)

    # Add testbench
    dut.input('lumi/testbench/testbench_lumi_ready.sv', package='umi')

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', 'lumi/testbench/config.vlt',
            package='umi')

    dut.build()

    # launch the simulation
    dut.simulate(
        plusargs=[
            ('valid_mode', 1),
            ('ready_mode', 1)
        ]
    )

    packets_req = gen_mergeable_umi_packets(num_bytes=65536,
                                            size=0,
                                            opcode_arr=[UmiCmd.UMI_REQ_READ,
                                                        UmiCmd.UMI_REQ_WRITE,
                                                        UmiCmd.UMI_REQ_POSTED,
                                                        UmiCmd.UMI_REQ_ATOMIC],
                                            bytes_per_tx=64)

    packets_resp = gen_mergeable_umi_packets(num_bytes=65536,
                                             size=0,
                                             opcode_arr=[UmiCmd.UMI_RESP_READ,
                                                         UmiCmd.UMI_RESP_WRITE],
                                             bytes_per_tx=64)

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    req = UmiTxRx("umi_req_in.q", "umi_req_out.q", fresh=True)
    resp = UmiTxRx("umi_resp_in.q", "umi_resp_out.q", fresh=True)

    print("### Starting test ###")

    procs = []

    procs.append(multiprocessing.Process(target=umi_loopback, args=(req, packets_req)))

    procs.append(multiprocessing.Process(target=umi_loopback, args=(resp, packets_resp)))

    for proc in procs:
        proc.start()

    for proc in procs:
        proc.join()


if __name__ == '__main__':
    main()
