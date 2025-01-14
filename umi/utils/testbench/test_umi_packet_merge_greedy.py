#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC

from switchboard import SbDut, UmiTxRx, random_umi_packet
from umi import sumi


def main():

    extra_args = {
        '--vldmode': dict(type=int, default=1, help='Valid mode'),
        '-n': dict(type=int, default=10, help='Number of transactions'
                   'to send during the test.')
    }

    dut = SbDut('testbench', cmdline=True, extra_args=extra_args,
                trace=False, trace_type='fst', default_main=False)

    # Set up inputs
    dut.input('utils/testbench/testbench_umi_packet_merge_greedy.v', package='umi')
    dut.input('utils/testbench/testbench_umi_packet_merge_greedy.cc', package='umi')

    dut.use(sumi)

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile',
            'file', 'config', 'utils/testbench/config.vlt', package='umi')
    dut.add('tool', 'verilator', 'task', 'compile', 'option', '--coverage')

    # Build simulator
    dut.build()

    # launch the simulation
    ret_val = dut.simulate(plusargs=[('valid_mode', dut.args.vldmode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    umi = UmiTxRx("client2rtl_0.q", "rtl2client_0.q", fresh=True)

    print("### Starting random test ###")

    n_sent = 0

    while (n_sent < dut.args.n):
        txp = random_umi_packet()
        if umi.send(txp, blocking=False):
            print('* TX *')
            print(str(txp))
            n_sent += 1

    ret_val.wait()


if __name__ == '__main__':
    main()
