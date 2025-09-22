import pytest
import siliconcompiler as sc
from siliconcompiler.flows import lintflow
import umi


def lint(design):
    proj = sc.Project(design)
    proj.add_fileset("rtl")
    proj.set_flow(lintflow.LintFlow())
    return proj.run()


@pytest.mark.parametrize("name", umi.sumi.__all__)
def test_lint_sumi(name):
    assert lint(getattr(umi.sumi, name)())
