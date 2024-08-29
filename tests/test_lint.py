from siliconcompiler import Chip
from siliconcompiler.flows import lintflow
import glob
import pytest
import umi
import shutil
from pathlib import Path


@pytest.fixture
def slang_chip():
    chip = Chip('lint')
    chip.use(lintflow, tool='slang')

    chip.use(umi)
    chip.set('option', 'flow', 'lintflow')

    return chip


@pytest.fixture
def slang():
    if shutil.which('slang') is None:
        pytest.skip('slang is not installed')


def __filelist():
    return glob.glob(str(Path(umi.__file__).parent / '**' / 'rtl' / '*.v'))


@pytest.mark.parametrize('file', __filelist())
def test_lint_slang(slang_chip, file):
    slang_chip.set('option', 'entrypoint', Path(file).stem)

    if slang_chip.get('option', 'entrypoint') == 'umi_packet_merge_greedy':
        pytest.skip(reason='File is outdaded and will be cleaned up later')

    slang_chip.input(file)
    slang_chip.run()

    assert slang_chip.get('record', 'toolexitcode', step='lint', index='0') == 0
