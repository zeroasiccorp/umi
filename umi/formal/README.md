# Formal property proofs

Machine-checked proofs of UMI spec properties against the RTL in this
repo, run with [SymbiYosys](https://symbiyosys.readthedocs.io)
(yosys + SMT solvers).

Each proof is two files. No generators, no copied RTL:

    <layer>/fv_<name>.sv     harness: instantiates the shipped RTL,
                             constrains inputs, states the properties
    <layer>/fv_<name>.sby    the sby job, one task per question

`[files]` paths reference the RTL in place. Shared property modules
(the checkers themselves) are normal blocks under `umi/sumi/`, e.g.
`umi/sumi/umi_checker/`. The directories sby creates during a run
(`fv_*_<task>/`) are build products: gitignored, never committed.

## Run

    # the whole lane (ordinary tasks must pass, fault_* tasks must fail)
    pytest -m formal tests/sumi/test_formal.py

    # one task by hand, from the proof's directory
    cd umi/formal/sumi && sby -f fv_umi_codec.sby prove

SiliconCompiler's sby flow can generate these jobs from the filesets;
planned as the CI lane once its formal API stabilizes (currently
engine-locked to boolector).

## Tools

`sby`, `yosys`, `boolector`, and `z3` on PATH. Easiest source is the
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases):

    source <extracted>/oss-cad-suite/environment

Plus the repo's python environment for the pytest lane; the test-tree
conftests import switchboard/cocotb, so collection fails without it:

    python3 -m venv .venv
    source .venv/bin/activate
    pip install -e .[test]

Without the tools on PATH the formal tests skip; they never break
other CI lanes.

## Conventions

* Tasks named `fault_*` inject a bug and must FAIL; all other tasks
  must PASS. The pytest lane enforces both directions (a fault task
  that passes is reported as the error it is).
* `prove` tasks are k-induction: a PASS is unbounded, not a bounded
  search. Every `cover` witness must be REACHED, or the environment
  is over-constrained.
* `prove` runs boolector, `prove_z3` runs z3; both must pass.

## Adding a proof

1. Add `fv_<name>.sv` + `fv_<name>.sby` under the layer directory,
   with at least one `fault_*` task and covers for assumed corners.
2. Add its tasks to the lists in `tests/sumi/test_formal.py`.
