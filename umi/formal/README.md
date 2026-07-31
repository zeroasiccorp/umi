# Formal property proofs

Machine-checked proofs of UMI spec properties against the RTL in this repo,
run with [SymbiYosys](https://symbiyosys.readthedocs.io) (yosys + SMT solvers).

Each proof is two files — no generators, no copied RTL:

    <layer>/fv_<name>.sv     harness: instantiates the shipped RTL,
                             constrains inputs, states the properties
    <layer>/fv_<name>.sby    the sby job, one task per question

`[files]` paths reference the RTL in place. Shared property modules (the
checkers) are normal blocks under `umi/sumi/`, e.g. `umi/sumi/umi_checker/`.
The `fv_*_<task>/` directories sby creates are build products: gitignored,
never committed.

**Each harness header documents its own properties, scope and fault table.**
This file is the index; the detail lives next to the code.

## Run

    # .sby lane -- every task, full solver matrix
    pytest -m formal tests/sumi/test_formal.py

    # SiliconCompiler lane -- same proofs as PropertyCheckFlow runs, with
    # the sby jobs generated from the repo's own Design filesets
    pytest -m formal tests/sumi/test_formal_sc.py

    # one task by hand
    cd umi/formal/sumi && sby -f fv_umi_codec.sby prove

CI runs both in the "Formal CI" job (`.github/workflows/ci.yml`) inside
`ghcr.io/siliconcompiler/sc_tools:latest`. It runs **serially** -- sby keeps a
per-proof status database that concurrent tasks of the same proof corrupt, so
this lane deliberately omits `-n`. The full set takes a few minutes.

## Tools

`sby`, `yosys`, `boolector` on PATH -- easiest via the
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases):

    source <extracted>/oss-cad-suite/environment

Plus the repo's python env for the pytest lanes (the test-tree conftests
import switchboard/cocotb, so collection fails without it):

    python3 -m venv .venv && source .venv/bin/activate && pip install -e .[test]

You need **both**: the python env alone collects the tests but every one
of them skips. If the whole lane reports `skipped`, `sby` is not on PATH.

The SiliconCompiler lane needs the same tools -- it generates sby jobs from
the Design filesets, it does not bundle a solver.

## Engines

**boolector gates everything.** It is the engine siliconcompiler's sby task
offers in the released 0.38.x versions, and the only solver in the CI
container.

`z3` and `bitwuzla` add independent-solver corroboration on the `.sby` lane
only (`prove_z3`, `prove_bw`, `prove_deep_bw`). Those rows skip wherever the
binary is absent -- notably in CI -- so install them locally if you want the
cross-check. The SiliconCompiler lane cannot use them: its sby task offers
boolector alone, because yosys' smtbmc drives solvers through the legacy
`--smt2` interface that current bitwuzla releases dropped.

## Conventions

* `fault_*` tasks inject a bug and **must FAIL**; every other task must PASS.
  The pytest lane enforces both directions -- a fault task that passes is
  reported as the error it is.
* `prove` tasks are k-induction: a PASS is **unbounded**, not a bounded search.
* Every `cover` witness must be REACHED, or the environment is over-constrained.
* A fault may falsify several related rules at once, and which label the solver
  reports can vary. Each `.sby` names the intended label per fault task.

## Proofs

| proof | judges | claim | green | fault |
|---|---|---|---|---|
| `sumi/fv_umi_codec` | `umi_pack` / `umi_unpack` | CMD codec round-trips over the 13 structured opcodes | 3 | 1 |
| `sumi/fv_umi_buffer` | `umi_buffer` | obeys the README 4.2 ready/valid handshake, including rule 5 | 5 | 3 |
| `sumi/fv_umi_demux` | `umi_demux` | routing, broadcast and fork conservation; every output channel legal SUMI; rule 5 clean | 6 | 6 |
| `sumi/fv_umi_arbiter` | `umi_arbiter` | grant contract: at most one grant, never to an idle or masked requester, and in priority mode the lowest unmasked requester wins | 6 | 3 |
| `sumi/fv_umi_cmd` | `umi_cmd_checker` | CMD-word legality: the checker's assume face and assert face agree | 5 | 10 |
| `sumi/fv_umi_txn` | `umi_txn_checker` | response-side transaction / framing against a perfect in-order responder | 6 | 8 |

`fv_umi_codec`, `fv_umi_buffer`, `fv_umi_demux` and `fv_umi_arbiter` prove
**shipped design RTL**. `fv_umi_cmd` and `fv_umi_txn` qualify the **checkers themselves** --
one face against the other -- which is what makes them safe to bind elsewhere.

### Scope notes

Only the caveats a reader must know before trusting a result; full rationale
is in each harness header.

**README 4.2 rule 5** ("the assertion of VALID must not depend on the assertion
of READY") is structural -- a cycle-sampled bind-in monitor cannot assert it.
It is proven harness-side instead, on the DUT: a `rule5` cover pins READY low
for the whole trace and reaches VALID asserting anyway, and `fault_rule5`
models the illegal design where VALID waits for READY, under which that cover
becomes unreachable and the task fails. `fv_umi_demux` adds a second,
independent form -- a self-composition miter proving `in_ready` does not depend
on `in_valid`. Both blocks are clean.

**`fv_umi_demux`** -- the onehot-select assumption is the boundary of correct
usage, not decoration. The `hazard` task drops it and witnesses both real
behaviours: `select==0` **accepts and silently drops** a beat, and a multi-hot
select **duplicates** it. `fault_drop` / `fault_dup` weaken the assumption in
each direction so it is falsifiable rather than trusted.

**`fv_umi_cmd`** -- `cover_sa` and `fault_sa_reserved` run the opt-in strict
profile `CHECK_SA_RESERVED=1` (request SA reserved bits zero). It defaults
**off**: the repo's own reference traffic uses the high SA bytes for routing.

**`fv_umi_txn`** -- three limits:

* **Framing depth.** `prove` runs MAXLEN=1 (up to two beats); `prove_deep`
  raises the harness LEN ceiling to MAXLEN=3 (four beats). Unbounded at each.
* **No interleave.** Holds for one point-to-point link with responses in
  request order. Bind the checker **before** any response mux; per-key
  (HOSTID) folding downstream of a merge is not covered.
* **Width.** The harness runs DW=64 (the checker ships DW=256) to keep the SMT
  problem tractable; the framing rules are DW-agnostic.

## Adding a proof

1. Add `fv_<name>.sv` + `fv_<name>.sby` under the layer directory, with at
   least one `fault_*` task and covers for every assumed corner.
2. Add its tasks to the lists in `tests/sumi/test_formal.py`.
3. Add a family entry (deps, depth, params) plus one green and one fault row
   in `tests/sumi/test_formal_sc.py` so it also rides the SiliconCompiler lane.
