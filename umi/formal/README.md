# Formal property proofs

Machine-checked proofs of UMI specification properties against the RTL in this
repository, run with [SymbiYosys](https://symbiyosys.readthedocs.io) through
siliconcompiler's `PropertyCheckFlow`.

One proof is one file: `<layer>/fv_<name>.sv` instantiates the shipped block,
constrains its inputs and states the properties. Each question it answers is a
row named `<family>:<task>` in `tests/test_formal_sc.py`.

That file is the matrix; this one is the index. Detail about any single proof
lives in its harness header.

## Run

    pytest -m formal tests/test_formal_sc.py            # all of it, ~6 min
    pytest -m formal tests/test_formal_sc.py -k 'buffer:'   # one family

You need `sby`, `yosys`, `yosys-abc` and `bitwuzla` on PATH -- easiest through
the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases) --
**and** the repo's python environment (`pip install -e .[test]`). With only the
python environment every row skips. CI runs the same lane inside
`ghcr.io/siliconcompiler/sc_tools:latest`.

To debug a row under sby directly, pin the build directory and reuse the job
file it generates:

    pytest -m formal tests/test_formal_sc.py -k 'buffer:identity' --basetemp=/tmp/f
    sby -f /tmp/f/*/fv_umi_buffer/job0/prove/0/sby/fv_umi_buffer.sby

When a row fails, the step sby names is one clock edge ahead of the VCD row
holding the violating values. Open the row *before* the one the log names.

## Proofs


| proof | judges | claim | green | fault |
|---|---|---|---|---|
| `sumi/fv_umi_codec` | `umi_pack` / `umi_unpack` | CMD codec round-trips over the 13 structured opcodes, and each field sits at the bit position `umi_messages.vh` defines | 2 | 1 |
| `sumi/fv_umi_buffer` | `umi_buffer` | obeys the README 4.2 ready/valid handshake, including rule 5, and delivers every beat unchanged in all four SUMI fields and in accept order, with none dropped or invented | 13 | 11 |
| `sumi/fv_umi_demux` | `umi_demux` | routing, broadcast and fork conservation; every output channel legal SUMI; rule 5 clean | 7 | 6 |
| `sumi/fv_umi_arbiter` | `umi_arbiter` | grant contract: at most one grant, never to an idle or masked requester, and in priority mode the lowest unmasked requester wins | 7 | 4 |
| `sumi/fv_umi_mux` | `umi_mux` | merge identity at accept time: one accept in iff one accept out, and the output beat is the accepting input's (bounded) | 4 | 3 |
| `sumi/fv_umi_mux2` | `umi_mux2` | select-and-merge: the output is the selected input's beat, accepts are conserved, and the output channel is legal SUMI under a stable select | 7 | 5 |
| `sumi/fv_umi_crossbar` | `umi_crossbar` | NxN routing at accept time: one delivery per output, the delivered beat is the delivering input's, and no masked path delivers | 6 | 5 |
| `sumi/fv_umi_pipeline` | `umi_pipeline` | the single-cycle register stage keeps the handshake and delivers every beat it accepts, once, in order, unchanged (unbounded -- every register is a port) | 9 | 6 |
| `sumi/fv_umi_decode` | `umi_decode` | the class outputs are mutually exclusive and complete, and on the legal opcode set each matches the full five-bit encoding the four-bit compares stand in for | 3 | 4 |
| `sumi/fv_umi_isolate` | `umi_isolate` | isolate high clamps the whole channel to zero and isolate low passes it through, over both build-time arms | 7 | 2 |
| `sumi/fv_umi_monitor` | `umi_monitor` | the passive tap reports a transfer on exactly the cycles README 4.2 rule 1 defines one | 4 | 1 |
| `sumi/fv_umi_fifo` | `umi_fifo` | handshake and carriage over both the stored and bypass paths: nothing dropped, duplicated, invented or reordered (bounded, clocks tied) | 7 | 4 |
| `sumi/fv_umi_stream` | `umi_stream` | a legal handshake on all four faces at once, the two UMI and the two USI (bounded, clocks tied) | 2 | 4 |
| `sumi/fv_umi_memif` | `umi_memif` | the nine atomic operations against their arithmetic, and the arm that resolves an undefined ATYPE | 2 | 4 |
| `sumi/fv_umi_regif` | `umi_regif` | the register interface answers the right kind of request and keeps the response handshake at `SAFE=0`; `SAFE=1` loses answers and is pinned | 5 | 4 |
| `sumi/fv_umi_endpoint` | `umi_endpoint` | request to memory operation to response: one memory op per request, the right response kind, back to the requester, and the answers owed are accounted for | 3 | 5 |
| `sumi/fv_umi_ram` | `umi_ram` | an answer is only offered to a port whose id bit it carries; the response channel's rule 3 failure is pinned (bounded) | 3 | 2 |
| `sumi/fv_umi_fifoflex` | `umi_fifoflex` | bytes are conserved across a width change at `SPLIT=0` and on the merge arm; `SPLIT=1` is pinned as not conserving them (bounded) | 4 | 3 |
| `sumi/fv_umi_switch` | `umi_switch` | the output handshake on every port, with the ready merge active across one and two outputs (bounded) | 4 | 1 |
| `sumi/fv_umi_cmd` | `umi_cmd_checker` | CMD-word legality: the checker's assume face and assert face agree | 6 | 11 |
| `sumi/fv_umi_txn` | `umi_txn_checker` | response-side transaction / framing against a perfect in-order responder | 5 | 8 |
| `sumi/fv_umi_frame` | `umi_frame_checker` | intra-message framing on a single channel, the request side included: the checker's assume face and assert face agree | 3 | 7 |
| `adapters/fv_umi2apb` | `umi2apb` | the AMBA APB requester face (phase order, hold, payload stability, and PSTRB inactive on a read) and the SUMI response the block builds for the request it served (bounded) | 3 | 6 |
| `adapters/fv_umi2axil` | `umi2axil` | the AXI4-Lite manager face: VALID hold and payload stability on the three channels the block owns, against a completer model that answers only what it was asked (bounded) | 3 | 6 |
| `adapters/fv_axil2umi` | `axil2umi` | the same AXI4-Lite law set from the subordinate side -- B and R asserted, AW/W/AR assumed -- plus the SUMI request channel the block drives (bounded) | 3 | 5 |
| `adapters/fv_axi2umi` | `axi2umi` | the AXI4 subordinate face including the burst obligations AXI4-Lite does not have: RID held across a burst, RLAST on beat ARLEN+1 and nowhere else (bounded) | 4 | 5 |
| `adapters/fv_tl2umi` | `tl2umi` | the TileLink-UL subordinate D channel: response-opcode legality, and that D holds still once offered -- which TileLink does not require, so it is claimed as a block property. The manager is held only to the TL-UL request rules it really has. The D-to-A correspondence laws are written but not proven -- see the harness header (bounded) | 2 | 3 |
| `adapters/fv_umi2tl` | `umi2tl` | the TileLink-UL manager A channel: opcode legality, address alignment, and that A holds still once offered -- a block property, not a TileLink rule; the size/mask consistency rule is pinned as a failure (bounded) | 2 | 3 |
| `adapters/fv_umi_address_remap` | `umi_address_remap` | local traffic leaves its address untouched, only DSTADDR may change, and the output channel keeps the handshake (unbounded) | 3 | 3 |
| `adapters/fv_umi_data_aggregator` | `umi_data_aggregator` | a merged output carries the address of the first beat that went into it, and the output channel keeps the handshake. Byte conservation is not asserted -- see the harness header (bounded) | 2 | 2 |

135 green rows and 134 fault rows, 269 in all, over 30 harnesses.

Twenty-seven of them judge **shipped design RTL**: every SUMI block on
a UMI path except `umi_memagent`, whose atomic unit is textually the same as
`umi_memif`'s but reaches no port without a memory round trip, and
`umi_tester`, which is test-bench infrastructure rather than a block on
a path; plus all six bus adapters, `umi_address_remap` and
`umi_data_aggregator`. `fv_umi_cmd`, `fv_umi_txn` and `fv_umi_frame` qualify
the **checkers themselves**. `fv_umi_cmd` does so one face against the other;
`fv_umi_txn` elaborates the asserting face alone, against a responder model, so
its ASSUME face is not covered (see the scope note below).

## What does not hold


Ten blocks do not satisfy a law a reader would expect, and each such
law has a row that REQUIRES the failure so it cannot regress into
silence -- thirteen rows over the ten blocks. Nothing is injected on
any of them: the shipped configuration is the subject.

| row | what it requires to fail | why |
|---|---|---|
| `regif:fault_safe` | `a_regif_outstanding` | at `SAFE=1`, the default, a second request is accepted while the first answer still stands and the response is overwritten |
| `endpoint:fault_cap` | `a_ep_outstanding` | the `REG=1` arm holds two answers, not one, so the `REG=0` accounting law does not carry over |
| `ram:fault_stable` | `RULE3_dstaddr_stable` | the broadcast response address moves while an answer is standing unaccepted |
| `fifoflex:fault_split` | `a_flex_conserve` | at `SPLIT=1`, the arm `umi_memagent` instantiates, more bytes are delivered than were accepted |
| `apb:fault_drop` | `a_apb_unsupported_dropped` | the block header says atomics and RDMA are "dropped silently"; `incoming_req` has no opcode term, so both start a real APB transfer |
| `apb:fault_strb` | `APB6_pstrb_read` | AMBA APB requires PSTRB inactive during a read; `umi2apb.v:140` ties every strobe high in both directions, with a `TODO: Support strobe` beside it |
| `axil:fault_lane` | `a_axil_wdata_lane` | the byte-lane shift amount `(req_data_shift << 3)` is evaluated at the 3-bit width of `req_data_shift`, so it is always zero and an unaligned access is never shifted into its lane |
| `axil:fault_data` | `RULE3_data_stable` | `udev_resp_data` is driven by `axi_rdata` with no term selecting the live response channel, so on a write response the UMI payload moves under a standing offer |
| `axil2:fault_concurrent` | `AXIL_r_hold` | `axi_awready` and `axi_arready` are the same expression, so a manager raising AWVALID and ARVALID together has both accepted on one edge; the response steering then drains the UMI answer on BREADY and RVALID falls without RREADY |
| `axi:fault_multi` | `AXI_r_id` | one `ar_id` register and no burst term on `s_axi_arready`, so a second read burst accepted while the first is still returning overwrites RID under a standing RVALID -- against the block's own claim that RID is "held constant for all beats" |
| `axi:fault_burst` | `AXI_rlast_count` | RLAST is copied from the UMI response EOM with no beat counter, so a device that miscounts produces an AXI protocol violation at this block's output rather than a UMI error |
| `tlm:fault_mask` | `TL_a_mask_size` | a one-byte request takes the `req_bytes == 1` arm of the size/mask table, which sets `a_size` to 1 -- two bytes -- beside a mask enabling a single lane, so `countones(a_mask)` is 1 where TileLink requires 2 |
| `remap:fault_cfg` | `RULE3_dstaddr_stable` | DSTADDR is a combinational function of `chipid`, the remap table and the `set_dstaddress_*` pins, so an integrator that moves any of them while a beat is standing unaccepted moves the payload under a standing VALID |

If any of these ever goes green, the block changed and the lane says so.

## Scope

Per-proof limits are in each harness header. The ones that apply broadly:

* **Bounded where it says bounded.** `prove` rows are unbounded and close by
  k-induction. `bmc` rows are bounded and are used where a proof would
  otherwise rest on state no port exposes; the harness header says why each
  time. Every adapter proof but `remap:prove` is bounded, and each runs at one
  width -- the configuration matrix covers the SUMI families only.
* **Clocks are tied** in `fv_umi_fifo`, `fv_umi_stream` and `fv_umi_fifoflex`.
  Those blocks span two domains through `la_asyncfifo` and the harnesses drive
  both from one clock, so nothing here says anything about true asynchrony.
* **Rules 5 and 6 of README 4.2 are structural.** They constrain what a signal
  may *depend on*, which no property sampled once per cycle can state. Rule 5
  is proven harness-side instead -- a cover that holds READY low for a whole
  trace and still reaches VALID, plus a fault row that must go unreachable.
  Rule 6 wants a self-composition miter (`fv_umi_demux`, `fv_umi_mux2`).
* **One solver.** Every SMT result rests on bitwuzla alone, pinned so an
  upstream default cannot move it. Three `fv_umi_buffer` rows run `abc pdr`
  instead -- the two identity proofs and the fault row that convicts them --
  because k-induction cannot close payload identity at all. In place of
  independent corroboration there is the fault matrix: 134 rows that each
  inject a bug and must each still produce a counterexample.
* **Two blocks are not exported.** `umi_switch` is deliberately kept out of
  `umi.sumi`, so `fv_umi_switch` imports it directly. `umi_packet_merge_greedy`
  does not elaborate -- `umi_packet_merge_greedy.v:158` reads signals declared
  at `:240-241`, and slang rejects the forward reference -- so it has no proof
  until that is fixed.
* **LUMI has no proofs here**, and neither does any data width above the
  per-harness value in the table above.

## Conventions

* `fault_*` rows inject a bug and **must FAIL**. Every other row must PASS.
  The lane enforces both directions, and a fault row that ERRORs rather than
  producing a counterexample stays red.
* Every `cover` must be REACHED, or the environment is over-constrained and
  the assertions above it may be holding vacuously.
* **A `cover` row says nothing about the assertions in the same harness** --
  sby does not evaluate them in cover mode. Read a `hazard` row as "this is
  reachable", never as "this is legal".
* A fault may break several related rules at once, so each fault row pins the
  label it is aimed at and the harness header records which.

## Writing a proof

A harness is one file with four parts: free stimulus, the block, whatever
constrains the environment, and the properties. The shape:

```systemverilog
module fv_umi_thing #(parameter CW = 32, AW = 64, DW = 64) (input wire clk);

    (* anyseq *) wire nreset;              // free, but low at time zero
    reg f_past_exists = 1'b0;
    always @(posedge clk) f_past_exists <= 1'b1;
    always @(*) if (!f_past_exists) assume (!nreset);

    (* anyseq *) wire in_valid, ...;       // the solver drives these

    umi_thing dut (...);                   // the shipped block, unmodified

    umi_handshake_checker #(.ASSUME (1)) env_in  (...);   // constrain input
    umi_handshake_checker #(.ASSUME (0)) chk_out (...);   // assert output

    always @(posedge clk)                  // your own law, over the ports
        if (nreset & f_past_exists & out_valid)
            a_thing_law : assert (...);

`ifdef FORMAL
    always @(posedge clk)                  // and a witness for every corner
        if (nreset & f_past_exists)
            c_thing_beat : cover (out_valid & out_ready);
`endif
endmodule
```

Write laws against state the **harness** tracks, never the block's own
registers -- comparing a block to itself proves nothing. Give every law a
`fault_*` define that breaks it on purpose, so the row can be shown failing.

Then add a family entry to `FAMILIES` in `tests/test_formal_sc.py`, one `Proof`
row per question in `GREEN` and `FAULTS`, and a line to the table above.
Follow `fv_umi_mux` for a block pulling in lambdalib, `fv_umi_buffer` for a
property needing `abc pdr`.

## Reusing a proof on your own block

The property modules under `umi/sumi/umi_checker/` are where the specification
is written down:

| module | what it states |
|---|---|
| `umi_handshake_checker` | the README 4.2 ready/valid rules, per channel |
| `umi_cmd_checker` | CMD-word legality: opcode, ATYPE, size, alignment, error encoding |
| `umi_frame_checker` | intra-message framing on one channel |
| `umi_txn_checker` | the README section 3 transaction rules: one answer per request, of the right kind, to the right address |

They work on any block with a UMI channel, including one that never goes near
this repository, and they all take the same `ASSUME` parameter: `1` constrains
a channel something else drives, `0` asserts a channel yours drives.

The demo below uses the handshake checker. The other three attach the same
way; reach for `umi_cmd_checker` if your block builds a CMD word rather than
passing one through, `umi_frame_checker` if it emits multi-beat messages, and
`umi_txn_checker` if it answers requests.

Three files. `xyz` is a registered pass-through; substitute your own block and
only the port connections change.

```verilog
// rtl/xyz.v
module xyz #(parameter CW = 32, AW = 64, DW = 256) (
    input clk, input nreset,
    input           umi_in_valid,  input  [CW-1:0] umi_in_cmd,
    input  [AW-1:0] umi_in_dstaddr, input [AW-1:0] umi_in_srcaddr,
    input  [DW-1:0] umi_in_data,   output          umi_in_ready,
    output          umi_out_valid, output [CW-1:0] umi_out_cmd,
    output [AW-1:0] umi_out_dstaddr, output [AW-1:0] umi_out_srcaddr,
    output [DW-1:0] umi_out_data,  input           umi_out_ready
);
   reg v_r; reg [CW-1:0] c_r; reg [AW-1:0] d_r, s_r; reg [DW-1:0] p_r;
   assign umi_in_ready = ~v_r | umi_out_ready;
   assign umi_out_valid = v_r;      assign umi_out_cmd     = c_r;
   assign umi_out_dstaddr = d_r;    assign umi_out_srcaddr = s_r;
   assign umi_out_data = p_r;
   always @(posedge clk or negedge nreset)
     if (!nreset)                          v_r <= 1'b0;
     else if (umi_in_valid & umi_in_ready) v_r <= 1'b1;
     else if (umi_out_ready)               v_r <= 1'b0;
   always @(posedge clk)
     if (umi_in_valid & umi_in_ready) begin
        c_r <= umi_in_cmd;     d_r <= umi_in_dstaddr;
        s_r <= umi_in_srcaddr; p_r <= umi_in_data;
     end
endmodule
```

```systemverilog
// formal/fv_xyz.sv
`default_nettype none
module fv_xyz #(parameter CW = 32, AW = 64, DW = 64) (input wire clk);

    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk) f_past_exists <= 1'b1;
    always @(*) if (!f_past_exists) assume (!nreset);

    (* anyseq *) wire          in_valid, out_ready;
    (* anyseq *) wire [CW-1:0] in_cmd;
    (* anyseq *) wire [AW-1:0] in_dstaddr, in_srcaddr;
    (* anyseq *) wire [DW-1:0] in_data;

    wire in_ready, out_valid;
    wire [CW-1:0] out_cmd;
    wire [AW-1:0] out_dstaddr, out_srcaddr;
    wire [DW-1:0] out_data;

    xyz #(.CW (CW), .AW (AW), .DW (DW)) dut (
        .clk (clk), .nreset (nreset),
        .umi_in_valid (in_valid), .umi_in_cmd (in_cmd),
        .umi_in_dstaddr (in_dstaddr), .umi_in_srcaddr (in_srcaddr),
        .umi_in_data (in_data), .umi_in_ready (in_ready),
        .umi_out_valid (out_valid), .umi_out_cmd (out_cmd),
        .umi_out_dstaddr (out_dstaddr), .umi_out_srcaddr (out_srcaddr),
        .umi_out_data (out_data), .umi_out_ready (out_ready));

    // ASSUME=1 on a channel something else drives: the rules constrain it
    umi_handshake_checker #(.CW (CW), .AW (AW), .DW (DW), .ASSUME (1))
    env_in (.clk (clk), .nreset (nreset),
            .valid (in_valid), .ready (in_ready), .cmd (in_cmd),
            .dstaddr (in_dstaddr), .srcaddr (in_srcaddr), .data (in_data));

    // ASSUME=0 on a channel your block drives: the rules are asserted
    umi_handshake_checker #(.CW (CW), .AW (AW), .DW (DW), .ASSUME (0))
    chk_out (.clk (clk), .nreset (nreset),
             .valid (out_valid), .ready (out_ready), .cmd (out_cmd),
             .dstaddr (out_dstaddr), .srcaddr (out_srcaddr), .data (out_data));
endmodule
`default_nettype wire
```

Instantiate them; never `bind`. yosys has dropped bind directives without
reporting it, and a dropped bind takes its assertions with it, so the run
returns `proved` having checked nothing.

```python
# test_formal_xyz.py
import shutil
from pathlib import Path
import pytest
from siliconcompiler import Design, Project
from siliconcompiler.flows.formalflow import PropertyCheckFlow, PropertyCheckMode
from siliconcompiler.tools.sby import SBYTask
from umi.common import UMI
from umi.sumi import Checker

HERE = Path(__file__).resolve().parent

pytestmark = pytest.mark.skipif(
    any(shutil.which(t) is None for t in ("sby", "yosys", "bitwuzla")),
    reason="formal toolchain not on PATH")


class XYZ(UMI):
    def __init__(self):
        super().__init__("xyz", files=["rtl/xyz.v"], deps=[Checker()])


def _project(mode):
    design = Design("fv_xyz")
    design.set_dataroot("fv_xyz", str(HERE / "formal"))
    with design.active_fileset("rtl"):
        design.set_topmodule("fv_xyz")
        design.add_file("fv_xyz.sv")
        design.add_depfileset(XYZ(), "rtl")
    proj = Project(design)
    proj.add_fileset("rtl")
    proj.set_flow(PropertyCheckFlow(f"formal_{mode}",
                                    modes=getattr(PropertyCheckMode, mode.upper())))
    proj.option.set_builddir(str(HERE / "build"))
    proj.option.set_novercheck(True)
    SBYTask.find_task(proj).set_sby_depth(10)
    SBYTask.find_task(proj).add_sby_engine("smtbmc bitwuzla", clobber=True)
    return proj


def test_xyz_bmc():
    assert _project("bmc").run().get("metric", "errors", step="bmc", index="0") == 0


def test_xyz_cover():
    assert _project("cover").run().get("metric", "errors", step="cover", index="0") == 0
```

    pytest test_formal_xyz.py -v        # 2 passed, about 1 s

README 4.2 rules 2 and 3 are now proven on `umi_out`, over every legal trace.

**Check it can fail before believing it.** Drop VALID whether or not the sink
took the beat:

```verilog
-    else if (umi_out_ready)               v_r <= 1'b0;
+    else                                  v_r <= 1'b0;
```

    Assert failed in fv_xyz.chk_out: RULE2_valid_hold

All four only say whether a channel is legal UMI. What your block is *for* is
a law you write yourself.

For simulation instead of proof, the same modules attach with `bind` --
`umi/sumi/umi_checker/testbench/` has a worked example with a `+inject` run
that must fail. Keep a run that must fail beside every run that must pass.
