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
 * output for one cycle, and under FV_FAULT_SWAP the observed beat
 * carries DSTADDR and SRCADDR exchanged for the whole trace. The proof
 * must then FAIL, with a counterexample trace. A checker that cannot
 * fail a broken design proves nothing about a working one; these tasks
 * are the checker's own regression.
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
 *
 * PAYLOAD IDENTITY (FV_IDENTITY; tasks `identity`, `identity_bypass`,
 * `identity_cover`, `fault_swap`). The handshake rules say WHEN a beat
 * moves, never WHICH beat: a buffer that exchanged DSTADDR and SRCADDR,
 * or handed its beats back out of order, obeys every one of them. Two
 * laws close that, both read off the ports:
 *
 *   a_id_occupancy  the beats taken in and not yet let out are exactly
 *                   the beats the buffer says it is holding, so none is
 *                   dropped, duplicated or invented. MODE 1 reads that
 *                   count off the two status outs -- EMPTY (valid 0,
 *                   ready 1), BUSY (1,1), FULL (1,0), both registered
 *                   from one next_state (umi_buffer.v:102-118), with
 *                   (0,0) ruled out by a_rule5_state above. MODE 0
 *                   stores nothing, so there the law is insert==remove.
 *   a_id_beat       the beat now offered is the beat that entered with
 *                   that beat number, whole: CMD, DSTADDR, SRCADDR and
 *                   DATA compared as one vector. Order rides along,
 *                   because the number IS the accept order -- a swapped
 *                   pair of beats delivers the wrong payload against it.
 *                   MODE 0 has no numbering to keep: the beat offered
 *                   IS the input beat, checked every cycle.
 *
 * The tracked beat number is (* anyconst *), held for the whole trace:
 * the solver picks which beat is checked, so proving the tracked one
 * proves every one, and no shadow queue is needed. Numbers are three
 * bits and wrap, which is sound because a buffer that holds at most two
 * beats -- a_id_occupancy is that bound -- retires a number long before
 * it comes round again.
 *
 * ENGINE. `identity` runs `abc pdr`, not the smtbmc k-induction every
 * other prove task here uses. Both are unbounded; what differs is where
 * the inductive invariant comes from. The skid register
 * (umi_buffer.v:90-93) reaches out_data only one cycle after a FULL
 * buffer drains, and no port shows it before then. k-induction starts
 * from an arbitrary state, so it starts from a FULL buffer whose skid
 * slot holds a value no accepted beat put there, keeps out_ready low
 * for the whole window, and reports `Assert failed in fv_umi_buffer:
 * a_id_beat`. No assertion written over ports alone can rule that start
 * out: two states differing only in the skid register are identical at
 * the boundary, and only one of them breaks the law. PDR derives its
 * invariant over the design's own registers instead, and closes the
 * property with no environment assumption -- in particular with no
 * bound on how long READY may stay low. fv_umi_mux settles for a
 * bounded task at this same fence, for the same reason: its captured
 * input is not port-observable either.
 *
 * Outside these two laws: progress (nothing here says a held beat is
 * ever delivered -- this file asserts no liveness property), latency,
 * and payload widths above the face the identity tasks run, which
 * fv_umi_buffer.sby sets and explains.
 ******************************************************************************/

`default_nettype none

module fv_umi_buffer #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64,
    parameter MODE = 1,             // 1: skid buffer, 0: bypass
    parameter [5:0] RULE_EN = 6'h3F // checker per-rule enables
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
    wire [PW-1:0] in_packet = {in_cmd, in_dstaddr, in_srcaddr, in_data};

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
        .in_data   (in_packet),
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

`ifdef FV_FAULT_SWAP
    // the observed beat carries DSTADDR and SRCADDR exchanged. The swap
    // is static, so VALID still holds and the observed payload is still
    // stable across a stall: every README 4.2 rule survives it and only
    // a_id_beat can break. That is the point of the task -- it is the
    // corruption the handshake checker is blind to by construction.
    wire [AW-1:0] obs_dstaddr = out_srcaddr;
    wire [AW-1:0] obs_srcaddr = out_dstaddr;
`else
    wire [AW-1:0] obs_dstaddr = out_dstaddr;
    wire [AW-1:0] obs_srcaddr = out_srcaddr;
`endif

    wire [CW-1:0] obs_cmd = out_cmd;

    // ----------------------------------------------------------------
    // the same file, both directions
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (1),                      // environment: assume legal input
        .RULE_EN (RULE_EN)
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
        .ASSUME (0),                      // requirement: assert legal output
        .RULE_EN (RULE_EN)
    ) chk_out (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (obs_valid),
        .ready   (out_ready),
        .cmd     (obs_cmd),
        .dstaddr (obs_dstaddr),
        .srcaddr (obs_srcaddr),
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

    // ----------------------------------------------------------------
    // PAYLOAD IDENTITY (FV_IDENTITY, see the file header). Every beat
    // that leaves is the beat that entered, unchanged in all four SUMI
    // fields and in accept order. Ports only: a beat enters on
    // in_valid & in_ready, leaves on the observed out_valid & out_ready,
    // and the buffer's occupancy is read off the two status outs.
    // ----------------------------------------------------------------
`ifdef FV_IDENTITY
    wire [PW-1:0] obs_packet = {obs_cmd, obs_dstaddr, obs_srcaddr, obs_data};

    wire insert = in_valid & in_ready;      // a beat enters
    wire remove = obs_valid & out_ready;    // a beat leaves

    generate
        if (MODE == 1) begin : g_id_skid
            // beat numbers, modulo 8. The buffer holds at most two, so a
            // number is always retired long before it comes round again.
            localparam IW = 3;

            reg [IW-1:0] in_cnt;
            reg [IW-1:0] out_cnt;
            always @(posedge clk or negedge nreset)
                if (!nreset) begin
                    in_cnt  <= {IW{1'b0}};
                    out_cnt <= {IW{1'b0}};
                end else begin
                    if (insert)
                        in_cnt  <= in_cnt  + {{(IW-1){1'b0}}, 1'b1};
                    if (remove)
                        out_cnt <= out_cnt + {{(IW-1){1'b0}}, 1'b1};
                end

            // ONE arbitrary beat number, constant for the whole trace.
            // The solver picks it, so proving the tracked beat proves
            // every beat -- no shadow queue needed for the claim.
            (* anyconst *) wire [IW-1:0] fv_beat;
            reg [PW-1:0] tracked;
            always @(posedge clk)
                if (insert && (in_cnt == fv_beat))
                    tracked <= in_packet;

            // occupancy the ports advertise: EMPTY (valid 0, ready 1),
            // BUSY (1,1), FULL (1,0). Both status outs are registered
            // from the same next_state, so this decode is exact and the
            // (0,0) corner is unreachable -- a_rule5_state above.
            wire [IW-1:0] port_occ = {{(IW-1){1'b0}}, obs_valid}
                                   + {{(IW-1){1'b0}}, ~in_ready};

            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset) begin
                    // nothing lost, nothing invented: the beats taken in
                    // and not yet let out are exactly the beats the
                    // buffer says it is holding
                    a_id_occupancy : assert ((in_cnt - out_cnt) == port_occ);
                    // and the beat now at the head is the tracked one,
                    // whole, whenever the tracked number is the one due
                    if (obs_valid && (out_cnt == fv_beat)
                                  && (in_cnt != out_cnt))
                        a_id_beat : assert (obs_packet == tracked);
                end

            // witnesses (formal-only): the claim is not vacuous -- the
            // tracked beat really is delivered, and the skid slot really
            // is used
`ifdef FORMAL
            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset) begin
                    c_id_deliver : cover (remove && (out_cnt == fv_beat));
                    c_id_full    : cover ((in_cnt - out_cnt)
                                          == {{(IW-2){1'b0}}, 2'd2});
                end
`endif

        end else begin : g_id_bypass
            // MODE 0 stores nothing: the output IS the input, so the two
            // laws collapse to a cycle-local pair. Same labels, same
            // claims -- accounting, then payload.
            always @(posedge clk)
                if (f_past_exists & nreset) begin
                    a_id_occupancy : assert (insert == remove);
                    if (obs_valid)
                        a_id_beat : assert (obs_packet == in_packet);
                end
        end
    endgenerate
`endif

endmodule

`default_nettype wire
