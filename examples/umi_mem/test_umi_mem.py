import sys

sys.path.append('../../umi/testbench')
import umi_testbench

import pytest

import umi_mem

@pytest.fixture(scope='module')
def chip_tb():
    '''Setup/compile the testbench.

    The decorator above this method ensures that this code executes once per
    test session, making it faster to run multiple tests at once.
    '''
    chip = umi_mem.setup()

    # Uncomment to enable VCD dumps for each test.
    #chip.set('option', 'trace', True)

    # Set a timeout for test execution in seconds. Useful since tests will
    # otherwise hang if the expected # of transactions are not received.
    chip.set('flowgraph', 'verification', 'execute', '0', 'timeout', 2)

    return umi_testbench.compile_tb(chip, 'umi_mem')

def test_1(chip_tb):
    chip_tb.set('input', 'txfile', 'tests/stimulus1.memh')
    chip_tb.set('input', 'rxfile', 'tests/expect1.memh')
    umi_testbench.run_tb(chip_tb, 'test_1')

def test_2(chip_tb):
    chip_tb.set('input', 'txfile', 'tests/stimulus2.memh')
    chip_tb.set('input', 'rxfile', 'tests/expect2.memh')
    umi_testbench.run_tb(chip_tb, 'test_2')
