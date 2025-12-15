import pytest
import os
import shutil


def pytest_addoption(parser):
    parser.addoption("--seed", type=int, action="store", help="Provide a fixed seed")

    helpstr = ("Run all tests in current working directory. Default is to run "
               "each test in an isolated per-test temporary directory.")

    parser.addoption(
        "--cwd", action="store_true", help=helpstr
    )

    helpstr = ("Remove test after run.")

    parser.addoption(
        "--clean", action="store_true", help=helpstr
    )


@pytest.fixture(autouse=True)
def test_wrapper(tmp_path, request, monkeypatch):
    '''Fixture that automatically runs each test in a test-specific temporary
    directory to avoid clutter. To override this functionality, pass in the
    --cwd flag when you invoke pytest.'''
    if not request.config.getoption("--cwd"):
        monkeypatch.chdir(tmp_path)

        # Run the test.
        yield

        if request.config.getoption("--clean"):
            monkeypatch.undo()
            shutil.rmtree(tmp_path)
    else:
        yield


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
