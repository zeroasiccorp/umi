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
 * Formal harness: umi_buffer against the README 4.2 handshake rules.
 *
 * The assume/guarantee split in one picture:
 *
 *              assumed legal            asserted legal
 *   (free) --[ env_in ASSUME=1 ]--> umi_buffer --[ chk_out ASSUME=0 ]--
 *
 * The input channel is free stimulus constrained to obey the rules
 * (the solver may only drive legal traffic); the output channel is
 * checked. Both directions use the SAME property file, so the
 * requirement and the environment can never drift apart.
 *
 * umi_buffer is payload-generic (one DW-wide data port), so the four
 * SUMI fields ride through it concatenated -- which also demonstrates
 * that the checker attaches to any block with two or three wires of
 * glue.
 *
 * Fault tasks (see fv_umi_buffer.sby): under FV_FAULT_VALID /
 * FV_FAULT_DATA the harness lets the solver corrupt the observed
 * output for one cycle. The proof must then FAIL, with a
 * counterexample trace. A checker that cannot fail a broken design
 * proves nothing about a working one; these tasks are the checker's
 * own regression.
 *
 * Rule 5 (README 4.2 rule 5, README.md:462): "The assertion of VALID
 * must not depend on the assertion of READY. In other words, it is not
 * legal for the VALID assertion to wait for the READY assertion." A
 * cycle-sampled bind-in monitor can not assert this structural rule
 * (see umi_handshake_checker's header); the complete method is
 * harness-level, on the DUT we prove, in three parts:
 *   1. STUCK-LOW WITNESS (`rule5` task, FV_RULE5_READYLOW): out_ready is
 *      assumed 0 on EVERY cycle, the upstream driver stays legal, and we
 *      COVER out_valid asserting -- and, per rule 2, holding. Reaching
 *      the cover with ready nailed low is the literal negation of "valid
 *      waits for ready": valid rises with zero help from ready.
 *   2. STATE-DRIVEN VALID (a_rule5_state, live in the prove tasks):
 *      out_valid is a pure function of internal occupancy, never of
 *      out_ready, read out at the ports. In the skid buffer the FULL
 *      state is port-visible as in_ready low, and `!in_ready |-> out_valid`
 *      says a full (data-holding) buffer always asserts VALID; in bypass
 *      `in_valid |-> out_valid`. Proven in both MODE=1 and MODE=0.
 *   3. TEETH (`fault_rule5` task, FV_FAULT_RULE5): models the illegal
 *      design in which valid waits for ready (out_valid & out_ready);
 *      under stuck-low ready that can never be covered, so the `rule5`
 *      cover goes unreachable and the task FAILs -- the honest cover has
 *      teeth.
 ******************************************************************************/

`default_nettype none

module fv_umi_buffer #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64,
    parameter MODE = 1              // 1: skid buffer, 0: bypass
) (
    input wire clk
);

    localparam PW = CW + AW + AW + DW;   // packed SUMI packet

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero (grounds all history)
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // free stimulus (constrained only by the rules, via env_in below)
    // ----------------------------------------------------------------
    (* anyseq *) wire            in_valid;
    (* anyseq *) wire [CW-1:0]   in_cmd;
    (* anyseq *) wire [AW-1:0]   in_dstaddr;
    (* anyseq *) wire [AW-1:0]   in_srcaddr;
    (* anyseq *) wire [DW-1:0]   in_data;
    (* anyseq *) wire            out_ready;

    wire        in_ready;
    wire        out_valid;
    wire [PW-1:0] out_packet;

    // ----------------------------------------------------------------
    // the design under test, exactly as shipped
    // ----------------------------------------------------------------
    umi_buffer #(
        .DW   (PW),
        .MODE (MODE)
    ) dut (
        .clk       (clk),
        .nreset    (nreset),
        .in_valid  (in_valid),
        .in_data   ({in_cmd, in_dstaddr, in_srcaddr, in_data}),
        .in_ready  (in_ready),
        .out_valid (out_valid),
        .out_data  (out_packet),
        .out_ready (out_ready)
    );

    wire [CW-1:0] out_cmd     = out_packet[PW-1          -: CW];
    wire [AW-1:0] out_dstaddr = out_packet[PW-CW-1       -: AW];
    wire [AW-1:0] out_srcaddr = out_packet[PW-CW-AW-1    -: AW];
    wire [DW-1:0] out_data    = out_packet[DW-1          -: DW];

    // ----------------------------------------------------------------
    // fault injection (formal known-answer tests -- see the .sby tasks)
    // ----------------------------------------------------------------
`ifdef FV_FAULT_VALID
    // the solver may drop the observed valid at any moment
    (* anyseq *) wire fault;
    wire obs_valid = out_valid & ~fault;
`else
    wire obs_valid = out_valid;
`endif

`ifdef FV_FAULT_DATA
    // the solver may flip the observed data lsb at any moment
    (* anyseq *) wire fault;
    wire [DW-1:0] obs_data = out_data ^ {{(DW-1){1'b0}}, fault};
`else
    wire [DW-1:0] obs_data = out_data;
`endif

    // ----------------------------------------------------------------
    // the same file, both directions
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (1)                       // environment: assume legal input
    ) env_in (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (in_valid),
        .ready   (in_ready),
        .cmd     (in_cmd),
        .dstaddr (in_dstaddr),
        .srcaddr (in_srcaddr),
        .data    (in_data)
    );

    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (0)                       // requirement: assert legal output
    ) chk_out (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (obs_valid),
        .ready   (out_ready),
        .cmd     (out_cmd),
        .dstaddr (out_dstaddr),
        .srcaddr (out_srcaddr),
        .data    (obs_data)
    );

    // ----------------------------------------------------------------
    // Rule 5 (README 4.2 rule 5, README.md:462): the assertion of VALID
    // must not depend on the assertion of READY -- it is not legal for
    // the VALID assertion to wait for the READY assertion. See the file
    // header for the three-part evidence; parts 1 and 3 live here under
    // FV_RULE5_READYLOW / FV_FAULT_RULE5, part 2 is a_rule5_state below.
    // ----------------------------------------------------------------
`ifdef FV_RULE5_READYLOW
`ifdef FV_FAULT_RULE5
    // ILLEGAL design model: VALID gated by READY (valid waits for ready).
    // Under stuck-low ready this is 0 forever, so the covers can not be
    // reached -- the `fault_rule5` task must FAIL.
    wire rule5_valid = out_valid & out_ready;
`else
    // honest DUT: VALID is whatever the buffer drives
    wire rule5_valid = out_valid;
`endif

    // pin the downstream ready low for the entire trace
    always @(*)
        assume (out_ready == 1'b0);

`ifdef FORMAL
    // asserted-then-held shadow register, initial-grounded (no $past)
    reg r5_past = 1'b0;
    always @(posedge clk)
        r5_past <= rule5_valid;

    always @(posedge clk) begin
        if (f_past_exists & nreset) begin
            // VALID asserts even though READY has been low all along
            c_rule5_valid_stuck_low : cover (rule5_valid);
            // and, per rule 2, stays asserted with READY still low
            c_rule5_valid_held      : cover (rule5_valid & r5_past);
        end
    end
`endif
`endif

    // ----------------------------------------------------------------
    // Part 2: STATE-DRIVEN VALID. out_valid is a pure function of the
    // buffer's internal occupancy, never of out_ready. Live in the prove
    // tasks (in cover/bmc modes the assert is inert). Occupancy is read
    // out at the ports -- no hierarchical peek into the DUT:
    //
    //   MODE 1 (skid): the buffer has two registered status outs, both
    //   assigned from the SAME next_state each cycle --
    //       out_valid == (state != EMPTY)   (data present)
    //       in_ready  == (state != FULL)    (room upstream)
    //   in_ready low is the port-visible "FULL, i.e. holding data" flag.
    //   The FSM never rests in the (out_valid=0, in_ready=0) corner: that
    //   would be a full buffer withholding VALID -- the exact signature
    //   of "VALID waits for READY". So `!in_ready |-> out_valid`: when the
    //   buffer is occupied to the point of backpressuring the input,
    //   out_valid is asserted with no dependence on out_ready. Both outs
    //   fall out of one next_state, so they can never both be low -- the
    //   property is inductive without reaching into the FSM register.
    //
    //   MODE 0 (bypass): the input payload is presented the same cycle,
    //   so in_valid implies out_valid; out_ready feeds only in_ready and
    //   can not gate out_valid.
    //
    // past_nreset gates out the reset edge, where both status outs are
    // held low by the repo's reset convention (not a rule-5 violation).
    // ----------------------------------------------------------------
    reg past_nreset = 1'b0;
    always @(posedge clk)
        past_nreset <= nreset;

    generate
        if (MODE == 1) begin : g_rule5_skid
            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset)
                    a_rule5_state : assert (in_ready || out_valid);
        end else begin : g_rule5_bypass
            always @(posedge clk)
                if (f_past_exists & nreset)
                    a_rule5_state : assert (!in_valid || out_valid);
        end
    endgenerate

endmodule

`default_nettype wire
