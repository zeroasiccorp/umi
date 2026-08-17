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
 * Formal harness: the umi_arbiter grant contract.
 *
 * umi_arbiter already carries `assert property ($onehot0(grants))` behind
 * `ifdef VERILATOR (umi_arbiter.v:95) -- a concurrent SVA that yosys does
 * not see and that the default simulation flow does not compile. This
 * harness proves that claim, and three more, unbounded.
 *
 * The grant network is combinational (umi_arbiter.v:79-90):
 *
 *     spec_requests = ~mask & ~thermometer & requests
 *     block[j]      = |spec_requests[j-1:0]
 *     grants        = spec_requests & ~block
 *
 * so a grant is the LOWEST-indexed eligible request. The only state is
 * the thermometer, which rotates priority across collisions.
 *
 * The rules:
 *
 *   a_arb_onehot0   at most one grant is asserted. Immediate from the
 *                   priority network: only the lowest set bit of
 *                   spec_requests survives `& ~block`.
 *   a_arb_subset    a grant implies a request -- the arbiter never
 *                   invents work.
 *   a_arb_nomask    a masked requester is never granted.
 *   a_arb_prio      in priority mode the granted index is the lowest
 *                   unmasked requester. Only meaningful with the mode
 *                   pinned, see below.
 *
 * The first three hold with `mode` completely FREE: they are invariants
 * of the priority network, not of a particular arbitration policy.
 *
 * MODE PINNING (`prio` task). The thermometer only advances when
 * `mode == 2'b10` (umi_arbiter.v:63), so under a mode pinned to 2'b00 it
 * stays at its reset value of zero and `spec_requests` reduces to
 * `~mask & requests`. That is what makes the lowest-index law
 * port-observable. The task assumes the mode for the whole trace.
 *
 * SCOPE NOTE -- the mode encoding. The port comment reads
 * "[00]=priority,[01]=roundrobin,[1x]=reserved" (umi_arbiter.v:29), but
 * the thermometer advances on `mode[1:0]==2'b10` (umi_arbiter.v:63), the
 * encoding that comment calls reserved. The documented round-robin mode
 * 2'b01 leaves the thermometer at zero, making it behave as priority.
 * This harness pins the encodings it proves rather than resolving the
 * discrepancy: `prio` uses 2'b00, and the rotation witness uses 2'b10
 * because that is where rotation actually happens.
 *
 * Fault rows corrupt only the OBSERVED grant vector, never the DUT, so
 * the proof must FAIL. A checker that cannot fail a broken design proves
 * nothing about a working one.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   arbiter:prove          N=4, mode free, unbounded
 *   arbiter:prove_n2       the same, N=2
 *   arbiter:prio           mode 2'b00, bounded (see MODE PINNING above)
 *   arbiter:cover          witnesses: expect all reached
 *   arbiter:rotate         mode 2'b10, the rotation witness
 *   arbiter:fault_*        must FAIL, labels below
 *
 * Fault rows and the assertion label each is intended to trip:
 *   fault_onehot   a_arb_onehot0   a second grant bit is lit, on an input
 *                                  that is itself requesting and unmasked.
 *                                  subset and nomask therefore still hold
 *                                  by construction and a_arb_onehot0 is
 *                                  the sole reported label.
 *   fault_subset   a_arb_subset    a grant appears on an input that is
 *                                  not requesting (sole).
 *   fault_mask     a_arb_nomask    a grant appears on a masked input
 *                                  (sole).
 *   fault_rotate   c_arb_rotate    the rotation witness with the
 *                                  thermometer inert (mode pinned 2'b00):
 *                                  the cover goes UNREACHED, so a
 *                                  c_arb_rotate that could be satisfied
 *                                  without rotation would show up here as
 *                                  a pass. Also reports c_arb_hold, which
 *                                  is likewise only reachable while the
 *                                  thermometer holds a requester off.
 * The intended label must appear in the log's failed-assertion list, or
 * for a cover row in its unreached-cover list.
 ******************************************************************************/

`default_nettype none

module fv_umi_arbiter #(
    parameter N = 4                 // number of requesters
) (
    input wire clk
);

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero so the thermometer starts
    // from its reset value rather than an arbitrary one
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // free stimulus -- the grant contract holds for ANY request pattern
    // ----------------------------------------------------------------
    (* anyseq *) wire [1:0]   mode_free;
    (* anyseq *) wire [N-1:0] mask;
    (* anyseq *) wire [N-1:0] requests;

`ifdef FV_MODE_PRIO
    // priority mode for the whole trace: the thermometer never advances,
    // so it holds its reset value and the lowest-index law is observable
    wire [1:0] mode = 2'b00;
`elsif FV_MODE_RR
`ifdef FV_FAULT_ROTATE
    // The rotation witness run with the thermometer INERT: mode 2'b00
    // never advances it, so the grant network is a pure function of the
    // request/mask pattern. c_arb_rotate holds that pattern still, so it
    // can only be reached by a thermometer advance and here goes
    // UNREACHED -- the row must FAIL.
    wire [1:0] mode = 2'b00;
`else
    // the encoding that actually rotates (see the scope note above)
    wire [1:0] mode = 2'b10;
`endif
`else
    wire [1:0] mode = mode_free;
`endif

    wire [N-1:0] grants;

    // ----------------------------------------------------------------
    // the design under test, exactly as shipped
    // ----------------------------------------------------------------
    umi_arbiter #(.N(N)) dut (
        .clk      (clk),
        .nreset   (nreset),
        .mode     (mode),
        .mask     (mask),
        .requests (requests),
        .grants   (grants));

    // ----------------------------------------------------------------
    // fault injection (formal known-answer tests -- one define per
    // fault row; the header tabulates the label each is intended to trip)
    // ----------------------------------------------------------------
`ifdef FV_FAULT_ONEHOT
    // A SECOND grant on another input that is also requesting and
    // unmasked. subset and nomask still hold by construction, so
    // a_arb_onehot0 is the only law that can break.
    (* anyseq *) wire [N-1:0] fbit;
    wire [N-1:0] extra = fbit & requests & ~mask & ~grants;
    always @(*) begin
        assume ($onehot(extra));
        assume (|grants);
    end
    wire [N-1:0] obs_grants = grants | extra;

`elsif FV_FAULT_SUBSET
    // A single grant on an input that is NOT requesting (and unmasked).
    // onehot0 and nomask still hold, so a_arb_subset is the only law
    // that can break.
    (* anyseq *) wire [N-1:0] fbit;
    wire [N-1:0] extra = fbit & ~requests & ~mask;
    always @(*)
        assume ($onehot(extra));
    wire [N-1:0] obs_grants = extra;

`elsif FV_FAULT_MASK
    // A single grant on an input that IS requesting but is masked.
    // onehot0 and subset still hold, so a_arb_nomask is the only law
    // that can break.
    (* anyseq *) wire [N-1:0] fbit;
    wire [N-1:0] extra = fbit & requests & mask;
    always @(*)
        assume ($onehot(extra));
    wire [N-1:0] obs_grants = extra;

`else
    wire [N-1:0] obs_grants = grants;
`endif

    // ----------------------------------------------------------------
    // the grant contract
    // ----------------------------------------------------------------
    wire [N-1:0] eligible = requests & ~mask;
    // isolate the lowest set bit: x & (~x + 1)
    wire [N-1:0] lowest   = eligible & (~eligible + {{(N-1){1'b0}}, 1'b1});

    always @(posedge clk) begin

        a_arb_onehot0 : assert ($onehot0(obs_grants));

        a_arb_subset : assert ((obs_grants & ~requests) == {N{1'b0}});

        a_arb_nomask : assert ((obs_grants & mask) == {N{1'b0}});

`ifdef FV_MODE_PRIO
        // with the thermometer at its reset value, the grant is exactly
        // the lowest-indexed eligible request. This is a REACHABILITY
        // property, not an inductive one: it holds on every trace from
        // reset, but k-induction may start the step case from a
        // fabricated state with a hot thermometer, which no real trace
        // can produce under a pinned priority mode. The task therefore
        // runs bounded (mode bmc) rather than claiming an unbounded
        // proof it cannot support.
        if (f_past_exists & nreset) begin
            a_arb_prio : assert (obs_grants == lowest);
        end
`endif
    end

    // ----------------------------------------------------------------
    // witnesses (formal-only)
    // ----------------------------------------------------------------
`ifdef FORMAL
    reg [N-1:0] prev_grants = {N{1'b0}};
    reg [N-1:0] prev_requests = {N{1'b0}};
    reg [N-1:0] prev_mask = {N{1'b0}};
    always @(posedge clk) begin
        prev_grants   <= grants;
        prev_requests <= requests;
        prev_mask     <= mask;
    end

    always @(posedge clk)
        if (f_past_exists & nreset) begin
            // an ordinary grant happens
            c_arb_grant   : cover (|grants);
            // two requesters compete and exactly one wins
            c_arb_contend : cover ((requests & ~mask) != (requests & ~mask & (~(requests & ~mask) + {{(N-1){1'b0}}, 1'b1}))
                                   && |grants);
            // requests are pending yet nothing is granted -- the
            // thermometer is holding them off (the RTL header calls this
            // the fill penalty; it is a real, reachable state)
            c_arb_hold    : cover (|(requests & ~mask) && !(|grants));
`ifdef FV_MODE_RR
            // the grant MOVES to a different requester while the request
            // and mask pattern is held still. The pattern clause is what
            // makes this a rotation witness: with the thermometer at its
            // reset value the grant is a pure function of
            // `requests & ~mask`, so a still pattern gives a still grant.
            // Only a thermometer advance can move it, which is exactly
            // the mechanism under witness. `fault_rotate` runs this same
            // cover with the thermometer inert and must go unreached.
            c_arb_rotate  : cover (|grants && |prev_grants
                                   && (grants != prev_grants)
                                   && (requests == prev_requests)
                                   && (mask == prev_mask));
`endif
        end
`endif

endmodule

`default_nettype wire
