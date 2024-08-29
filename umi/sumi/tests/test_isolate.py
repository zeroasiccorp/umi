#!/usr/bin/env python3

# Copyright (C) 2024 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest
from switchboard import UmiTxRx, umi_loopback


def test_isolate(sumi_dut, valid_mode, ready_mode):

    # launch the simulation
    sumi_dut.simulate(plusargs=[('valid_mode', valid_mode), ('ready_mode', ready_mode)])

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx("host2dut_0.q", "dut2host_0.q", fresh=True)

    print("### Starting test ###")

    umi_loopback(host, 1000, max_bytes=32)


if __name__ == '__main__':
    pytest.main(['-s', '-q', __file__])
