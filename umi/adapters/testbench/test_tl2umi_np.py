#!/usr/bin/env python3

from siliconcompiler import Chip
from siliconcompiler.flows import dvflow
from siliconcompiler.package import path as sc_path
from umi import sumi


def build():
    chip = Chip('tb_tl2umi_np')
    chip.use(sumi)
    chip.use(dvflow, tool='icarus')

    chip.set('option', 'flow', 'dvflow')

    chip.input('utils/testbench/tb_tl2umi_np.v', package='umi')

    memfile = f"{sc_path(chip, 'umi')}/utils/testbench/buffer.memh"

    chip.add('tool', 'execute', 'task', 'exec_input', 'option', f'+MEMHFILE={memfile}')

    chip.run()


if __name__ == "__main__":
    build()
