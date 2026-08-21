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
 * Fault rows: under FV_FAULT_VALID / FV_FAULT_DATA the harness lets
 * the solver corrupt the observed output for one cycle, under
 * FV_FAULT_SWAP the observed beat carries DSTADDR and SRCADDR
 * exchanged for the whole trace, and under FV_FAULT_FREEOUT the whole
 * observed channel is free (the mask rows, below). The proof must then
 * FAIL, with a counterexample trace. A checker that cannot fail a broken
 * design proves nothing about a working one; these rows are the
 * checker's own regression.
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
 * PAYLOAD IDENTITY (FV_IDENTITY; rows `identity`, `identity_bypass`,
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
 * other prove row here uses. Both are unbounded; what differs is where
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
 * bounded row at this same fence, for the same reason: its captured
 * input is not port-observable either.
 *
 * WHAT PDR REPORTS. abc names a failing property by its AIGER output
 * index, not by label. sby can translate that back through a witness
 * replay, but the step needs an SMT solver beyond the four this lane
 * requires and aborts on these harnesses with a witness signal
 * mismatch, turning a genuine FAIL into a tool ERROR. The lane runs the
 * pdr rows with `aigsmt none` so the engine's own verdict stands, and
 * `fault_swap_pdr` is therefore a verdict-only row: it shows this engine
 * convicts a broken buffer, while `fault_swap` -- the same corruption
 * under bmc -- pins the label to a_id_beat.
 *
 * The identity rows run a narrower face than the rest of this harness,
 * AW=16 and DW=32, because PDR relates the payload registers bit by
 * bit. The law is width-agnostic -- the datapath is bit-parallel -- and
 * the two params on those rows are the whole change needed to widen it;
 * the harness defaults (AW=64, DW=64) close too, about five times
 * slower.
 *
 * Outside these two laws: progress (nothing here says a held beat is
 * ever delivered -- this file asserts no liveness property), latency,
 * and payload widths above that face.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   buffer:prove            MODE=1 skid buffer, unbounded
 *   buffer:bypass           MODE=0, unbounded
 *   buffer:cover            witnesses: expect all reached
 *   buffer:rule5            rule 4.2.5 witness (part 1 above)
 *   buffer:prove_mask_off   RULE_EN=0, see below
 *   buffer:identity         a_id_occupancy + a_id_beat, MODE=1, abc pdr
 *   buffer:identity_bypass  the same two labels, MODE=0, abc pdr
 *   buffer:identity_cover   the tracked beat is really delivered
 *                           (c_id_deliver) and the skid slot is really
 *                           used (c_id_full), so neither law is passing
 *                           vacuously
 *   buffer:identity_cover_bypass  the same job for the MODE=0 arm, which
 *                           states the two laws over different logic: a
 *                           beat really passes through (c_id_deliver) and
 *                           an offer really stands unaccepted
 *                           (c_id_stall), the case a_id_beat covers that
 *                           a delivery alone would not reach
 *   buffer:fault_valid      must FAIL, chk_out.RULE2_valid_hold
 *   buffer:fault_data       must FAIL, chk_out.RULE3_data_stable
 *   buffer:fault_rule5      must FAIL: FV_FAULT_RULE5 models the
 *                           illegal design where VALID waits for READY
 *                           (out_valid & out_ready). Under stuck-low
 *                           ready the covered signal is 0 forever, so
 *                           c_rule5_valid_stuck_low and
 *                           c_rule5_valid_held both go UNREACHED and
 *                           the row FAILs -- the honest rule5 cover has
 *                           teeth
 *   buffer:fault_swap       must FAIL, a_id_beat alone: FV_FAULT_SWAP
 *                           exchanges DSTADDR and SRCADDR on the
 *                           OBSERVED beat only, and the swap is static,
 *                           so VALID still holds and the payload is
 *                           still stable across a stall -- every
 *                           handshake rule survives it. That corruption
 *                           is exactly what the handshake rows cannot
 *                           see, which is why the identity laws are here
 *   buffer:fault_swap_pdr   the same corruption on the abc pdr engine
 *                           the identity rows are proven with, so that
 *                           engine is shown convicting a broken buffer
 *                           and not only answering "proved". Verdict
 *                           only -- see WHAT PDR REPORTS above
 *   buffer:fault_mask_*     must FAIL, one per RULE_EN bit -- see below
 *
 * THE PER-RULE MASK. RULE_EN is checked in both directions, over every
 * bit, by one configuration: FV_FAULT_FREEOUT makes the OBSERVED output
 * channel entirely free -- VALID and all four payload fields, in reset
 * and out of it -- so every rule the handshake checker can raise is
 * falsifiable at once. Then
 *   prove_mask_off   RULE_EN=0: nothing is reported. A rule left outside
 *                    its RULE_EN guard would be falsified here at once.
 *   fault_mask_r2 / _r3cmd / _r3dst / _r3src / _r3data / _reset
 *                    one bit set per row: each must FAIL, and must name
 *                    that bit's own rule. Every bit is load-bearing or
 *                    one of these six rows would pass.
 * A targeted fault reaches one bit only -- FV_FAULT_VALID, for instance,
 * can only ever break RULE2_valid_hold -- which is why the mask rows use
 * the free channel instead. The DUT-level a_rule5_state assertion is not
 * a checker rule and stays live throughout, which keeps prove_mask_off a
 * proof and not an empty one.
 *
 * Both rule5 rows carry FV_NO_WITNESS so the handshake checker's own
 * transaction covers (valid & ready), unreachable under stuck-low ready,
 * do not spuriously fail the cover run.
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
    // fault injection (formal known-answer tests -- one define per
    // fault row; the header tabulates the label each is intended to trip)
    // ----------------------------------------------------------------
`ifdef FV_FAULT_FREEOUT
    // The observed output channel is ENTIRELY free -- VALID and all four
    // payload fields, in reset and out of it. Every rule the handshake
    // checker can raise is then falsifiable on this channel at once,
    // which is what gives the RULE_EN matrix (the mask rows below) teeth
    // on every bit rather than on the one bit a targeted fault happens
    // to break. The DUT is untouched, as in every other fault row here.
    (* anyseq *) wire            obs_valid;
    (* anyseq *) wire [CW-1:0]   obs_cmd;
    (* anyseq *) wire [AW-1:0]   obs_dstaddr;
    (* anyseq *) wire [AW-1:0]   obs_srcaddr;
    (* anyseq *) wire [DW-1:0]   obs_data;
`else

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

`endif  // FV_FAULT_FREEOUT

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

            // witnesses (formal-only): neither law is passing on an idle
            // link. c_id_deliver reaches the cycle a_id_occupancy calls a
            // matched insert/remove, c_id_stall reaches an offer standing
            // unaccepted -- the case a_id_beat covers that a delivery
            // alone would not
`ifdef FORMAL
            always @(posedge clk)
                if (f_past_exists & nreset) begin
                    c_id_deliver : cover (insert && remove);
                    c_id_stall   : cover (obs_valid && !out_ready);
                end
`endif
        end
    endgenerate
`endif

endmodule

`default_nettype wire
