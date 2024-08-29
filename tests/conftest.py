import pytest
from switchboard import SbDut
import os
from pathlib import Path
from umi import sumi
from fasteners import InterProcessLock
import multiprocessing


@pytest.fixture(autouse=True)
def test_wrapper(tmp_path):
    '''
    Fixture that automatically runs each test in a test-specific temporary
    directory to avoid clutter.
    '''

    topdir = os.getcwd()
    os.chdir(tmp_path)

    # Run the test.
    yield

    os.chdir(topdir)
