import pytest
from switchboard import SbDut
import os
from pathlib import Path
from umi import sumi
from fasteners import InterProcessLock
import multiprocessing


def pytest_collection_modifyitems(items):
    for item in items:
        if "sumi_dut" in getattr(item, "fixturenames", ()):
            item.add_marker("switchboard")
            pass


@pytest.fixture(autouse=True)
def test_wrapper(tmp_path):
    '''
    Fixture that automatically runs each test in a test-specific temporary
    directory to avoid clutter.
    '''
    try:
        multiprocessing.set_start_method('fork')
    except RuntimeError:
        pass

    topdir = os.getcwd()
    os.chdir(tmp_path)

    # Run the test.
    yield

    os.chdir(topdir)


@pytest.fixture
def build_dir(pytestconfig):
    return pytestconfig.cache.mkdir('sumi_build')


@pytest.fixture
def sumi_dut(build_dir, request):
    dut = SbDut('testbench', default_main=True, trace=False)

    dut.use(sumi)

    # Add testbench
    test_file_name = Path(request.fspath).stem
    assert (test_file_name[:5] == 'test_'), "Test file name must start with test_"
    testbench_name = f'sumi/testbench/testbench_{test_file_name[5:]}.sv'
    dut.input(testbench_name, package='umi')

    # TODO: How to add module/testbench specific parameters
    # dut.add('option', 'define', f'SPLIT={int(split)}')

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', 'sumi/testbench/config.vlt',
            package='umi')

    # Build simulator
    dut.set('option', 'builddir', build_dir / test_file_name)
    with InterProcessLock(build_dir / f'{test_file_name}.lock'):
        # ensure build only happens once
        # https://github.com/pytest-dev/pytest-xdist/blob/v3.6.1/docs/how-to.rst#making-session-scoped-fixtures-execute-only-once
        dut.build(fast=True)

    yield dut

    dut.terminate()


def pytest_addoption(parser):
    parser.addoption("--seed", type=int, action="store", help="Provide a fixed seed")


@pytest.fixture
def random_seed(request):
    fixed_seed = request.config.getoption("--seed")
    if fixed_seed is not None:
        test_seed = fixed_seed
    else:
        test_seed = os.getpid()
    yield test_seed
    print(f'Random seed used: {test_seed}')
