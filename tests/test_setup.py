import pytest
import umi


@pytest.mark.parametrize("name", umi.sumi.__all__)
def test_setup_sumi(name):
    assert getattr(umi.sumi, name)().check_filepaths()


@pytest.mark.parametrize("name", umi.adapters.__all__)
def test_setup_adapters(name):
    assert getattr(umi.adapters, name)().check_filepaths()
