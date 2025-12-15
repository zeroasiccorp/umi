#!/usr/bin/env python3

# Copyright (C) 2023 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import random
import numpy as np
from switchboard import SbDut, UmiTxRx
from switchboard.verilog.sim.switchboard_sim import SwitchboardSim
from siliconcompiler import Design
from umi.adapters import UMI2APB
from lambdalib.ramlib import Spram


class Umi2ApbTb(Design):

    def __init__(self):
        super().__init__("Umi2ApbTb")

        top_module = "testbench"

        self.set_dataroot('localroot', __file__)

        files = [
            "testbench_umi2apb.sv"
        ]

        deps = [
            UMI2APB(),
            Spram()
        ]

        with self.active_fileset('rtl'):
            self.set_topmodule(top_module)
            for item in files:
                self.add_file(item)
            for item in deps:
                self.add_depfileset(item)

        with self.active_fileset('verilator'):
            self.set_topmodule(top_module)
            self.add_depfileset(self, "rtl")
            self.add_depfileset(SwitchboardSim())

        with self.active_fileset('icarus'):
            self.set_topmodule(top_module)
            self.add_depfileset(self, "rtl")
            self.add_depfileset(SwitchboardSim())


def main():

    extra_args = {
        '--vldmode': dict(type=int, default=1, help='Valid mode'),
        '--rdymode': dict(type=int, default=1, help='Ready mode'),
        '-n': dict(type=int, default=10, help='Number of transactions'
                   'to send during the test.')
    }

    dut = SbDut(
        design=Umi2ApbTb(),
        fileset="verilator",
        tool="verilator",
        cmdline=True,
        extra_args=extra_args,
        trace=False
    )

    dut.build()

    # launch the simulation
    dut.simulate(
        plusargs=[
            ('valid_mode', dut.args.vldmode),
            ('ready_mode', dut.args.rdymode)
        ]
    )

    # instantiate TX and RX queues.  note that these can be instantiated without
    # specifying a URI, in which case the URI can be specified later via the
    # "init" method

    host = UmiTxRx("host2dut_0.q", "dut2host_0.q", fresh=True)

    print("### Starting test ###")

    # regif accesses are all 32b wide and aligned
    for _ in range(dut.args.n):
        addr = np.random.randint(0, 512) * 4
        # length should not cross the DW boundary - umi_mem_agent limitation
        data = np.uint32(random.randrange(2**32-1))

        print(f"umi writing 0x{data:08x} to addr 0x{addr:08x}")
        host.write(addr, data)

        print(f"umi read from addr 0x{addr:08x}")
        val = host.read(addr, np.uint32)
        if not (val == data):
            print(f"ERROR umi read from addr 0x{addr:08x} expected {data} actual {val}")
            assert (val == data)

    print("### TEST PASS ###")


if __name__ == '__main__':
    main()
