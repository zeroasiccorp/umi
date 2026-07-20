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

## Proofs

| proof | property module | claim | green tasks | fault tasks |
|---|---|---|---|---|
| `sumi/fv_umi_codec` | (umi_pack / umi_unpack) | CMD codec round-trips over the 13 structured opcodes | prove, prove_z3, cover | fault_eom |
| `sumi/fv_umi_buffer` | `umi_checker/rtl/umi_handshake_checker.sv` | umi_buffer obeys the README 4.2 ready/valid handshake | prove, prove_z3, bypass, cover | fault_valid, fault_data |
| `sumi/fv_umi_cmd` | `umi_checker/rtl/umi_cmd_checker.sv` | CMD-word legality: the assume face (legal-traffic generator) and assert face of the checker agree, at DW=256 and DW=64, and every legal opcode plus a full-capacity beat is reachable | prove, prove_z3, prove_dw64, cover, cover_sa | fault_opcode, fault_atype, fault_align_da, fault_align_sa, fault_fullbyte, fault_ex, fault_errsize, fault_cap, fault_respdata, fault_sa_reserved |

`fv_umi_cmd` checks one rule per fault task (the label each must trip
is tabulated in `fv_umi_cmd.sby`); `cover_sa` and `fault_sa_reserved`
run with the opt-in strict profile `CHECK_SA_RESERVED=1` (request SA
reserved bits zero), which defaults off because the repo's own
reference traffic uses the high SA bytes as routing/control bits.
