from pathlib import Path

import pytest

from umi.adapters.umi2apb.umi2apb import UMI2APB


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
def test_umi2apb(simulator, output_wave=False):
    from run_cocotb_sim import load_cocotb_test
    path = Path(__file__).parent
    files = [
        path / "test_basic_WR.py",
        path / "test_backpressure.py",
        path / "test_full_throughput.py",
        path / "test_posted_write.py",
        path / "test_random_stimulus.py"
    ]
    load_cocotb_test(
        design=UMI2APB(),
        topmodule="umi2apb",
        cocotb_files=files,
        simulator=simulator,
        trace=output_wave,
        seed=None
    )
