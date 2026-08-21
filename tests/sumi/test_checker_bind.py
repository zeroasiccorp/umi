"""The worked bind example: umi_handshake_checker attached to umi_buffer.

umi/sumi/umi_checker/testbench/umi_buffer_checker_bind.sv binds one
checker instance to each SUMI channel of umi_buffer without editing the
design, and tb_umi_buffer_bind.sv drives that buffer through a stall and
a drain. This runner builds the example with Verilator and checks both
runs.

The "+inject" run is the negative control. It breaks README 4.2 rule 3
on the channel the testbench itself drives, so the input-side bound
instance must report it, by name. Without that run a green clean run
would say nothing: with the two bind directives commented out, the same
injected violation goes unreported and the example still exits zero.

Verilator is the simulator here because Icarus does not support bind.
"""
import shutil
import subprocess
from pathlib import Path

import pytest

SUMI = Path(__file__).resolve().parents[2] / "umi" / "sumi"
TESTBENCH = SUMI / "umi_checker" / "testbench"

pytestmark = [
    pytest.mark.eda,
    pytest.mark.skipif(shutil.which("verilator") is None,
                       reason="Verilator not on PATH"),
]

SOURCES = [
    TESTBENCH / "tb_umi_buffer_bind.sv",
    TESTBENCH / "umi_buffer_checker_bind.sv",
    SUMI / "umi_checker" / "rtl" / "umi_handshake_checker.sv",
    SUMI / "umi_buffer" / "rtl" / "umi_buffer.v",
]

# the bound instance that must report the planted violation, and the
# rule it must report; a failure naming this path is the proof that the
# bind survived elaboration and that the assertion was evaluated
BOUND_INSTANCE = "tb_umi_buffer_bind.dut.u_umi_hs_in"
BOUND_RULE = "RULE3_cmd_stable"


@pytest.fixture
def example():
    """Build the example. --assert turns on assertion checking and
    --timing is needed for the testbench's event controls. Per test,
    because each test runs in its own temporary directory."""
    r = subprocess.run(
        ["verilator", "--binary", "--assert", "--timing", "-o", "example"]
        + [str(s) for s in SOURCES],
        capture_output=True, text=True, timeout=600)
    assert r.returncode == 0, r.stdout + r.stderr
    return Path("obj_dir") / "example"


def _run(binary, *args):
    r = subprocess.run([str(binary), *args],
                       capture_output=True, text=True, timeout=300)
    return r.returncode, r.stdout + r.stderr


def test_bind_example_clean(example):
    """Legal traffic into a correct buffer: both bound instances silent."""
    rc, out = _run(example)
    assert rc == 0, out
    assert "EXAMPLE PASS" in out, out
    assert "Assertion failed" not in out, out


def test_bind_example_violation_is_reported(example):
    """The negative control. One rule 3 break on the channel the
    testbench drives, which the input-side bound instance must report."""
    rc, out = _run(example, "+inject")
    assert rc != 0, out
    assert f"{BOUND_INSTANCE}.g_assert.{BOUND_RULE}" in out, out
    assert "EXAMPLE PASS" not in out, out
