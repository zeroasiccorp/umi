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
            #item.add_marker("switchboard")
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
    dut = SbDut('testbench', default_main=True, trace=True)

    dut.use(sumi)

    # Add testbench
    test_file_name = Path(request.fspath).stem
    testbench_name = test_file_name.replace('test', 'sumi/testbench/testbench') + ".sv"
    dut.input(testbench_name, package='umi')

    # TODO: How to add module/testbench specific parameters
    #dut.add('option', 'define', f'SPLIT={int(split)}')

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


@pytest.fixture(params=[0, 1, 2])
def valid_mode(request):
    return request.param


@pytest.fixture(params=[0, 1, 2])
def ready_mode(request):
    return request.param
