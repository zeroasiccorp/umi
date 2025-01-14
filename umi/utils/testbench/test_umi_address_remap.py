#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC

import random
from argparse import ArgumentParser
from switchboard import SbDut, UmiTxRx, random_umi_packet
from umi import sumi


def main():

    extra_args = {
        '--vldmode': dict(type=int, default=1, help='Valid mode'),
        '--rdymode': dict(type=int, default=1, help='Ready mode'),
        '-n': dict(type=int, default=10, help='Number of transactions'
                   'to send during the test.')
    }

    dut = SbDut('testbench', cmdline=True, extra_args=extra_args,
                trace=False, trace_type='fst', default_main=True)

    # Set up inputs
    dut.input('utils/testbench/testbench_umi_address_remap.v', package='umi')

    dut.use(sumi)

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile',
            'file', 'config', 'utils/testbench/config.vlt', package='umi')

    # Build simulator
    dut.build()

    # launch the simulation
    dut.simulate(plusargs=[('valid_mode', dut.args.vldmode),
                           ('ready_mode', dut.args.rdymode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    umi = UmiTxRx("client2rtl_0.q", "rtl2client_0.q", fresh=True)

    print("### Starting random test ###")

    n_sent = 0
    n_recv = 0
    txq = []

    while (n_sent < dut.args.n) or (n_recv < dut.args.n):
        addr = random.randrange(0x0000_0000_0000_0000, 0x0000_07FF_FFFF_FFFF)
        addr = addr & 0xFFFF_FF00_0000_FFF0  # Allow different devices but reduce address space per device

        txp = random_umi_packet(dstaddr=addr, srcaddr=0x0000110000000000)
        if n_sent < dut.args.n:
            if umi.send(txp, blocking=False):
                print(f"Transaction sent: {n_sent}")
                print(str(txp))
                txq.append(txp)
                # Offset
                if ((addr >= 0x0000_0600_0000_0080) and
                        (addr <= 0x0000_06FF_FFFF_FFFF)):
                    addr = addr - 0x0000_0000_0000_0080
                    txq[-1].dstaddr = addr
                # Remap
                elif ((addr & 0xFFFF_FF00_0000_0000) != 0x0000_0400_0000_0000):
                    addr = addr ^ 0x00FF_FF00_0000_0000
                    txq[-1].dstaddr = addr
                n_sent += 1

        if n_recv < dut.args.n:
            rxp = umi.recv(blocking=False)
            if rxp is not None:
                print(f"Transaction received: {n_recv}")
                print(str(rxp))
                if rxp != txq[0]:
                    raise Exception(f'Mismatch! {n_recv}')
                else:
                    txq.pop(0)
                    n_recv += 1


if __name__ == '__main__':
    main()
