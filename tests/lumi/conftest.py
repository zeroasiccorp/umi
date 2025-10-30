import pytest
from switchboard import SbDut
from umi import lumi
from fasteners import InterProcessLock


def pytest_collection_modifyitems(items):
    for item in items:
        if "lumi_dut" in getattr(item, "fixturenames", ()):
            item.add_marker("switchboard")
            pass


@pytest.fixture
def build_dir(pytestconfig):
    return pytestconfig.cache.mkdir('lumi_build')


@pytest.fixture
def lumi_dut(build_dir, request):

    dut = SbDut('testbench', default_main=True, trace=False)

    # dut = SbDut('testbench', cmdline=True,
    #             default_main=True, trace=True, trace_type='vcd')

    dut.use(lumi)

    # Add testbench
    dut.input('lumi/testbench/testbench_lumi.sv', package='umi')

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', 'lumi/testbench/config.vlt',
            package='umi')

    # Build simulator
    dut.set('option', 'builddir', build_dir / lumi.__name__)
    with InterProcessLock(build_dir / f'{lumi.__name__}.lock'):
        # ensure build only happens once
        # https://github.com/pytest-dev/pytest-xdist/blob/v3.6.1/docs/how-to.rst#making-session-scoped-fixtures-execute-only-once
        dut.build(fast=True)

    yield dut

    dut.terminate()


@pytest.fixture(params=("2d", "3d"))
def chip_topo(request):
    return request.param
