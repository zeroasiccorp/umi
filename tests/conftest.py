import pytest
import os
import multiprocessing


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


def pytest_addoption(parser):
    parser.addoption("--seed", type=int, action="store", help="Provide a fixed seed")


@pytest.fixture(autouse=True)
def random_seed(request):
    fixed_seed = request.config.getoption("--seed")
    if fixed_seed is not None:
        test_seed = fixed_seed
    else:
        test_seed = os.getpid()
    print(f'Random seed used: {test_seed}')
    yield test_seed
    print(f'Random seed used: {test_seed}')
