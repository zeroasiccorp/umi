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

A block that instantiates lambdalib has **no `.sby`** — lambdalib resolves out
of site-packages, and a committed job file cannot name that path portably.
Those proofs are harness-only and run through the SiliconCompiler lane, which
assembles sources from the block's own `Design` dependency graph.
`fv_umi_mux` and `fv_umi_crossbar` are of that kind.

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
  `bmc` tasks are bounded, and are used where a proof would otherwise rest on
  DUT-internal state; the harness header says why in each case.
* Every `cover` witness must be REACHED, or the environment is over-constrained.
* A fault may falsify several related rules at once, and which label the solver
  reports can vary. Each `.sby` names the intended label per fault task.
* Rule identifiers are stable names, not a contiguous sequence. A gap in the
  numbering means a candidate rule was considered and not adopted; every
  identifier that appears is defined by the checker that implements it.

## Proofs

| proof | judges | claim | green | fault |
|---|---|---|---|---|
| `sumi/fv_umi_codec` | `umi_pack` / `umi_unpack` | CMD codec round-trips over the 13 structured opcodes | 3 | 1 |
| `sumi/fv_umi_buffer` | `umi_buffer` | obeys the README 4.2 ready/valid handshake, including rule 5 | 5 | 3 |
| `sumi/fv_umi_demux` | `umi_demux` | routing, broadcast and fork conservation; every output channel legal SUMI; rule 5 clean | 6 | 6 |
| `sumi/fv_umi_arbiter` | `umi_arbiter` | grant contract: at most one grant, never to an idle or masked requester, and in priority mode the lowest unmasked requester wins | 6 | 3 |
| `sumi/fv_umi_mux` | `umi_mux` | merge identity at accept time: one accept in ⇔ one accept out, and the output beat is the accepting input's (bounded; SC lane only) | 2 | 3 |
| `sumi/fv_umi_crossbar` | `umi_crossbar` | NxN routing at accept time: one delivery per output, the delivered beat is the delivering input's, and no masked path delivers (SC lane only) | 2 | 5 |
| `sumi/fv_umi_cmd` | `umi_cmd_checker` | CMD-word legality: the checker's assume face and assert face agree | 5 | 10 |
| `sumi/fv_umi_txn` | `umi_txn_checker` | response-side transaction / framing against a perfect in-order responder | 6 | 8 |

`fv_umi_codec`, `fv_umi_buffer`, `fv_umi_demux`, `fv_umi_arbiter`, `fv_umi_mux`
and `fv_umi_crossbar` judge **shipped design RTL**. `fv_umi_cmd` and `fv_umi_txn` qualify
the **checkers themselves** -- one face against the other -- which is what makes
them safe to bind elsewhere.

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

**`fv_umi_mux`** -- three limits, all in the harness header:

* **Bounded, not unbounded.** The captured `stalled_input` is not observable at
  the ports while the output is stalled, so k-induction starts from states no
  trace reaches. Closing it wants an assume/guarantee stub licensed by
  `fv_umi_arbiter`'s grant contract, not a hierarchical peek.
* **Output stability across a stall is not claimed**, and no `ASSUME=0` checker
  is bound to the output channel. The arbiter re-evaluates every cycle, so
  consumers must sample on accept, not on offer.
* **Rule 5 is not claimed input-side.** `umi_in_ready` is combinational in
  `umi_in_valid` through the arbiter, so the argument `fv_umi_buffer` and
  `fv_umi_demux` make does not transfer here. `c_mux_r5_path` witnesses the
  dependency instead of leaving it as a reading of the source.

**`fv_umi_crossbar`** -- unbounded (`prove` closes by k-induction), with three
limits, all in the harness header:

* **Conservation is conditional.** "An output accept means an input was
  accepted" is claimed only for cycles in which every input requests at most
  one output. That is an antecedent of `a_xb_conserve` alone -- the other five
  laws, including the whole route theorem, are unconditional and hold under
  multicast. Outside it, an input granted by two outputs but taken by only one
  leaves that output accepting a beat the still-stalled input will offer again;
  `c_xb_multicast` witnesses the trace.
* **READY alone is not an accept.** `umi_in_ready` is a conjunction over the
  outputs an input requests, so an input requesting nothing reads ready
  (`c_xb_quiet`). Every law here qualifies ready with the input's request
  column, and a consumer must do the same.
* **Output channels are not checked as SUMI, and rule 5 is not claimed
  input-side** -- the same two limits `fv_umi_mux` records, for the same
  reason: the arbiter re-evaluates every cycle, and `umi_in_ready` is
  combinational in `umi_in_request` through it. Rule 6 is the one that
  governs a READY-on-VALID path; rule 5 constrains the opposite direction and
  is not claimed here either way. `c_xb_r6_path` witnesses the dependency.

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

If the block instantiates lambdalib, skip the `.sby` and steps 2 — the
SiliconCompiler lane is the only portable home. Follow `fv_umi_mux`.
