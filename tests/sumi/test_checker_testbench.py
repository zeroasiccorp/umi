"""Simulation self-tests for the umi_checker protocol checkers.

umi/sumi/umi_checker/testbench/ ships one self-checking testbench per
checker, alongside the worked bind example that tests/sumi/
test_checker_bind.py drives. This runner covers the four testbenches,
not the bind example. Each is run twice: a clean pass over legal
traffic, and a
"+inject" pass carrying exactly one planted protocol violation that the
checker must report. This runner drives both passes with Icarus Verilog
and checks the printed output.

The exit code alone is not a sufficient verdict, and each testbench
header says so:

  * the handshake testbench ends in $finish on both passes, so its
    inject pass exits zero even though the checker fired;
  * the command, transaction and frame testbenches end in $fatal
    whenever their own expectation disagrees with the checker, so a
    MISSED detection also exits nonzero.

The text is what separates the outcomes. A clean pass must print
"TB PASS" and no checker error at all; an inject pass must print the
expected checker error and no "TB FAIL".

Icarus is the simulator here because all four testbenches run correctly
under it. Verilator defers $finish to the end of the time step, so the
statements guarding those verdicts still execute after the clean pass
has asked to stop.
"""
import shutil
import subprocess
from pathlib import Path

import pytest

CHECKER = Path(__file__).resolve().parents[2] / "umi" / "sumi" / "umi_checker"
INCLUDE = Path(__file__).resolve().parents[2] / "umi" / "sumi" / "include"

_TOOLS = ("iverilog", "vvp")

pytestmark = [
    pytest.mark.eda,
    pytest.mark.skipif(any(shutil.which(t) is None for t in _TOOLS),
                       reason="Icarus Verilog (iverilog/vvp) not on PATH"),
]

# checker name, the message tag it prints on any violation, the specific
# error the inject pass must produce, and whether that pass ends in
# $fatal. The handshake testbench has no verdict of its own to disagree
# with, so it is the only one whose inject pass exits zero.
CASES = [
    ("handshake", "UMI-HS", "UMI-HS RULE3", False),
    ("cmd", "UMI-CMD", "UMI-CMD CMD-1", True),
    ("txn", "UMI-TXN", "UMI-TXN da_cont", True),
    ("frame", "UMI-FRAME", "UMI-FRAME size", True),
]


def _compile(name):
    """Build one testbench against the checker it exercises."""
    vvp = Path(f"tb_umi_{name}_checker.vvp")
    r = subprocess.run(
        ["iverilog", "-g2012", "-I", str(INCLUDE), "-o", str(vvp),
         str(CHECKER / "testbench" / f"tb_umi_{name}_checker.sv"),
         str(CHECKER / "rtl" / f"umi_{name}_checker.sv")],
        capture_output=True, text=True, timeout=300)
    assert r.returncode == 0, r.stdout + r.stderr
    return vvp


def _run(vvp, *args):
    r = subprocess.run(["vvp", str(vvp), *args],
                       capture_output=True, text=True, timeout=300)
    return r.returncode, r.stdout + r.stderr


@pytest.mark.parametrize("name,tag,error,inject_fatal", CASES,
                         ids=[c[0] for c in CASES])
def test_checker_testbench(name, tag, error, inject_fatal):
    vvp = _compile(name)

    # clean pass: legal traffic only, so the checker must stay silent
    rc, out = _run(vvp)
    assert rc == 0, out
    assert "TB PASS" in out, out
    assert "TB FAIL" not in out, out
    assert tag not in out, out

    # inject pass: one planted violation, which the checker must name.
    # "TB FAIL" here would mean the testbench and the checker disagreed
    # about the planted beat, i.e. the checker missed it.
    rc, out = _run(vvp, "+inject")
    assert error in out, out
    assert "TB FAIL" not in out, out
    assert (rc != 0) == inject_fatal, out
