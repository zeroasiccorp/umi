/*******************************************************************************
 * Copyright 2026 Zero ASIC Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ----
 *
 * Documentation:
 *
 * - Proves the passive bus monitor umi_monitor reports a transfer on
 *   exactly the cycles README.md section 4.2 rule 1 defines one, and
 *   on no others:
 *
 *     a_mon_beat  beat is high if and only if VALID and READY are both
 *                 high on that cycle
 *
 * SCOPE, stated plainly. Outside `SIMULATION the whole block is one
 * combinational assign (umi_monitor.v:59), so this is a small law and
 * the row is worth what a small law is worth: it holds the definition
 * of a transfer to the one in the specification, and the fault row
 * makes sure it is still being checked. Everything else the block does
 * -- the stall timeout, the opcode trace -- lives under `SIMULATION and
 * is not compiled into a formal build, so nothing here speaks to it.
 *
 * The block drives no bus signal: its only output is beat
 * (umi_monitor.v:50). That is a property of the port list, settled at
 * elaboration by the parametrized lint in tests/test_lint.py, and no
 * assertion here restates it.
 *
 * ONE LAW, DELIBERATELY. A cumulative version -- the beats reported
 * since reset equal the transfers that occurred -- was written and
 * then removed: a_mon_beat pins the wire on every cycle, so the two
 * counts are equal by construction and the second assertion could not
 * fail unless the first already had. It would have added a label to
 * the inventory and no evidence. The beat counter that remains feeds
 * c_mon_run only, as a witness that the link really moved several
 * beats, and nothing asserts on it.
 *
 * ROWS (tests/test_formal_sc.py):
 *   monitor:prove       a_mon_beat, unbounded
 *   monitor:cover       witnesses: expect all reached
 *   monitor:fault_or    must FAIL, a_mon_beat -- beat driven from
 *                       VALID or READY instead of both
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_monitor #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64
) (
    input wire clk
);

    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    (* anyseq *) wire          valid;
    (* anyseq *) wire          ready;
    (* anyseq *) wire [CW-1:0] cmd;
    (* anyseq *) wire [AW-1:0] dstaddr;
    (* anyseq *) wire [AW-1:0] srcaddr;
    (* anyseq *) wire [DW-1:0] data;

    wire beat;

    umi_monitor #(
        .CW (CW), .AW (AW), .DW (DW)
    ) dut (
        .valid   (valid),
        .ready   (ready),
        .cmd     (cmd),
        .dstaddr (dstaddr),
        .srcaddr (srcaddr),
        .data    (data),
        .clk     (clk),
        .nreset  (nreset),
        .beat    (beat)
    );

    // ----------------------------------------------------------------
    // observed output: the faults corrupt what the laws see, never the
    // DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------

`ifdef FV_FAULT_OR
    // the classic mis-reading of rule 1: either signal rather than both
    wire obs_beat = valid | ready;
`else
    wire obs_beat = beat;
`endif

    // ----------------------------------------------------------------
    // the transfer definition
    // ----------------------------------------------------------------
    always @(*) begin
        a_mon_beat : assert (obs_beat == (valid & ready));
    end

    // counted for the witness below only -- nothing asserts on this
    localparam KW = 6;                     // cycle counts, modulo 64

    reg [KW-1:0] beats_seen;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            beats_seen <= {KW{1'b0}};
        else if (obs_beat)
            beats_seen <= beats_seen + {{(KW-1){1'b0}}, 1'b1};

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset) begin
            c_mon_beat  : cover (obs_beat);
            // the two cycles a_mon_beat separates: an offer with no
            // taker, and a taker with no offer
            c_mon_stall : cover (valid & ~ready & ~obs_beat);
            c_mon_idle  : cover (~valid & ready & ~obs_beat);
            // and a run of transfers, so a_mon_beat is not passing on
            // a link that moved at most one beat
            c_mon_run   : cover (beats_seen == {{(KW-2){1'b0}}, 2'd3});
        end
`endif

endmodule

`default_nettype wire
