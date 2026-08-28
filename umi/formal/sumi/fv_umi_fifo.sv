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
 * - Proves umi_fifo keeps the SUMI handshake (README.md section 4.2
 *   rules 2 and 3) and carries every beat it accepts through in order,
 *   over both of its paths: the stored path (BYPASS=0) and the
 *   combinational bypass (BYPASS=1).
 *
 * ONE CLOCK. THIS IS THE SCOPE, AND IT IS A REAL LIMIT. umi_fifo is a
 * dual-clock block: it wraps la_asyncfifo, whose read and write
 * pointers cross between the two domains through gray coding and
 * la_drsync synchronisers. This harness ties umi_in_clk to umi_out_clk
 * and umi_in_nreset to umi_out_nreset and proves the block in that one
 * configuration.
 *
 * What that buys: every bug that does not depend on the clock ratio --
 * pointer arithmetic, full and empty derivation, the datapath, the
 * bypass multiplexers, ordering.
 *
 * What it does NOT buy, and no row here should be read as claiming:
 * anything about true asynchrony. Metastability is not in the Verilog
 * semantics at all, so a synchroniser proves nothing against silicon
 * until the properties are re-run against a model that lets the synced
 * value arrive a cycle late. That model does not exist in this
 * directory yet. Until it does, umi_fifo is judged single-clock, and
 * the async behaviour is unverified rather than verified.
 *
 * BOUNDED, NOT UNBOUNDED. These rows run bmc. The pointers reach
 * la_drsync registers that no port shows, so k-induction starts its
 * step case from pointer states that disagree with the beats actually
 * in the memory, and reports a violation no trace can reach. The same
 * fence umi_buffer met at its skid register and fv_umi_mux meets at its
 * captured input. umi_buffer got past it with abc pdr; that engine does
 * not converge on this block at these widths inside the lane's
 * timeout, so the honest result is a bounded one and it is labelled
 * bounded.
 *
 * WIDTHS. CW=32, AW=32, DW=64 -- the narrowest face the specification
 * actually permits (README 4.1: CW is 32, AW is 32 or 64, DW starts at
 * 64). The laws are width-agnostic because the datapath is
 * bit-parallel and carried as one vector.
 *
 * DEPTH. The handshake rows run the block default of 4. The carriage
 * rows pin DEPTH=2, the smallest depth that still fills, wraps its
 * pointers and drains, because the bounded search cost grows with the
 * stored state: the same rows at DEPTH=4 take eight times as long for
 * a law that does not mention DEPTH. Sweeping it belongs with the rest
 * of the configuration matrix, not in every run of the lane.
 *
 * LAWS.
 *   RULE2_valid_hold / RULE3_*_stable   the handshake at the output,
 *                     with the input constrained to be legal by the
 *                     same checker in its ASSUME face
 *   a_fifo_no_overflow  beats accepted and not yet delivered never
 *                     exceed DEPTH, so nothing is written over
 *   a_fifo_no_underflow  a beat is never delivered while the block is
 *                     holding none, so nothing is invented
 *   a_fifo_beat       the beat delivered with a given number is the
 *                     beat accepted with that number, whole: CMD,
 *                     DSTADDR, SRCADDR and DATA compared as one
 *                     vector. Order rides along, because the number IS
 *                     the accept order
 *
 * The two counting laws are inequalities on purpose. rd_empty is
 * derived from a pointer that has crossed a synchroniser, so it lags
 * the true occupancy even with the clocks tied; an equality against it
 * would be asserting the lag away.
 *
 * chaosmode is declared by umi_fifo and never read (its only
 * appearance is the port declaration), so it is tied low here and no
 * property depends on it.
 *
 * Outside these laws: progress (nothing here says an accepted beat is
 * ever delivered -- this file asserts no liveness property), clock
 * ratios, and reset skew between the two domains.
 *
 * ROWS (tests/test_formal_sc.py):
 *   fifo:bmc              handshake, stored path, bounded
 *   fifo:bmc_bypass       handshake, bypass path, bounded
 *   fifo:cover            witnesses: expect all reached
 *   fifo:identity         the three carriage laws, stored path, DEPTH=2
 *   fifo:identity_bypass  the same labels over the bypass path, which
 *                         stores nothing, so they collapse to a
 *                         cycle-local pair (see g_id_bypass)
 *   fifo:identity_cover   the tracked beat is really delivered, the
 *                         memory really fills, so no law passes
 *                         vacuously
 *   fifo:identity_cover_bypass  the same job for the bypass arm
 *   fifo:fault_valid      must FAIL, chk_out.RULE2_valid_hold
 *   fifo:fault_data       must FAIL, chk_out.RULE3_data_stable
 *   fifo:fault_swap       must FAIL, a_fifo_beat
 *   fifo:fault_ghost      must FAIL, a_fifo_no_underflow
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_fifo #(
    parameter CW     = 32,
    parameter AW     = 32,
    parameter DW     = 64,
    parameter DEPTH  = 4,
    parameter BYPASS = 0,
    parameter [5:0] RULE_EN = 6'h3F
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

    reg past_nreset = 1'b0;
    always @(posedge clk)
        past_nreset <= nreset;

    // ----------------------------------------------------------------
    // free stimulus (constrained only by the rules, via env_in below)
    // ----------------------------------------------------------------
    (* anyseq *) wire          in_valid;
    (* anyseq *) wire [CW-1:0] in_cmd;
    (* anyseq *) wire [AW-1:0] in_dstaddr;
    (* anyseq *) wire [AW-1:0] in_srcaddr;
    (* anyseq *) wire [DW-1:0] in_data;
    (* anyseq *) wire          out_ready;

    wire          in_ready;
    wire          out_valid;
    wire [CW-1:0] out_cmd;
    wire [AW-1:0] out_dstaddr;
    wire [AW-1:0] out_srcaddr;
    wire [DW-1:0] out_data;
    wire          fifo_full;
    wire          fifo_almost_full;
    wire          fifo_empty;

    wire [PW-1:0] in_packet = {in_cmd, in_dstaddr, in_srcaddr, in_data};

    // both domains driven from the one clock and reset: see ONE CLOCK
    umi_fifo #(
        .DEPTH (DEPTH), .CW (CW), .AW (AW), .DW (DW)
    ) dut (
        .bypass           (BYPASS[0]),
        .chaosmode        (1'b0),
        .fifo_full        (fifo_full),
        .fifo_almost_full (fifo_almost_full),
        .fifo_empty       (fifo_empty),
        .umi_in_clk       (clk),
        .umi_in_nreset    (nreset),
        .umi_in_valid     (in_valid),
        .umi_in_cmd       (in_cmd),
        .umi_in_dstaddr   (in_dstaddr),
        .umi_in_srcaddr   (in_srcaddr),
        .umi_in_data      (in_data),
        .umi_in_ready     (in_ready),
        .umi_out_clk      (clk),
        .umi_out_nreset   (nreset),
        .umi_out_valid    (out_valid),
        .umi_out_cmd      (out_cmd),
        .umi_out_dstaddr  (out_dstaddr),
        .umi_out_srcaddr  (out_srcaddr),
        .umi_out_data     (out_data),
        .umi_out_ready    (out_ready),
        .vdd              (1'b1),
        .vss              (1'b0)
    );

    // ----------------------------------------------------------------
    // observed output channel: the faults corrupt what the checker and
    // the carriage laws see, never the DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;
    (* anyseq *) wire f_ghost;

`ifdef FV_FAULT_VALID
    // an offer withdrawn without being accepted: rule 2
    wire obs_valid = out_valid & ~f_glitch;
`elsif FV_FAULT_GHOST
    // a beat the block never accepted, offered anyway. Made a LEGAL
    // offer -- it rises out of reset and changes only on a cycle the
    // receiver accepts -- so the handshake rules still hold and only
    // the accounting law can report it.
    reg ghost_q;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            ghost_q <= 1'b0;
        else if (out_ready)
            ghost_q <= f_ghost;
    wire obs_valid = out_valid | ghost_q;
`else
    wire obs_valid = out_valid;
`endif

`ifdef FV_FAULT_DATA
    // payload moving underneath a standing offer: rule 3
    wire [DW-1:0] obs_data = out_data ^ {DW{f_glitch}};
`else
    wire [DW-1:0] obs_data = out_data;
`endif

`ifdef FV_FAULT_SWAP
    // the two addresses exchanged: every handshake rule still holds --
    // the swap is stable and the timing untouched -- and only the
    // carriage law can see it
    wire [AW-1:0] obs_dstaddr = out_srcaddr;
    wire [AW-1:0] obs_srcaddr = out_dstaddr;
`else
    wire [AW-1:0] obs_dstaddr = out_dstaddr;
    wire [AW-1:0] obs_srcaddr = out_srcaddr;
`endif

    wire [PW-1:0] obs_packet = {out_cmd, obs_dstaddr, obs_srcaddr, obs_data};

    // ----------------------------------------------------------------
    // the handshake, both faces of one rule list
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
        .cmd     (out_cmd),
        .dstaddr (obs_dstaddr),
        .srcaddr (obs_srcaddr),
        .data    (obs_data)
    );

    // ----------------------------------------------------------------
    // carriage: nothing dropped, duplicated, invented or reordered
    //
    // Kept off the handshake rows on purpose: the accounting laws read
    // the same obs_valid the handshake faults corrupt and would report
    // a cycle ahead of the rule those rows are aimed at.
    // ----------------------------------------------------------------
`ifdef FV_IDENTITY
    wire insert = in_valid  & in_ready;    // accepted at the input
    wire remove = obs_valid & out_ready;   // delivered at the output

    localparam IW = 4;                     // beat numbers, modulo 16

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

    // ONE arbitrary beat number, constant for the whole trace. The
    // solver picks it, so proving the tracked beat proves every beat.
    (* anyconst *) wire [IW-1:0] fv_beat;
    reg [PW-1:0] tracked;
    always @(posedge clk)
        if (insert && (in_cnt == fv_beat))
            tracked <= in_packet;

    wire [IW-1:0] occ = in_cnt - out_cnt;

    generate
        if (BYPASS == 0) begin : g_id_stored
            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset) begin
                    a_fifo_no_overflow  : assert (occ <= DEPTH[IW-1:0]);
                    a_fifo_no_underflow : assert (!remove
                                                  || (occ != {IW{1'b0}}));
                    if (remove && (out_cnt == fv_beat))
                        a_fifo_beat : assert (obs_packet == tracked);
                end

            // witnesses: no carriage law is passing on an idle link
            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset) begin
                    c_fifo_deliver : cover (remove && (out_cnt == fv_beat));
                    c_fifo_b2b     : cover (insert && remove);
                    // the memory really fills, so the capacity law is
                    // not passing on a link that never queued anything
                    c_fifo_full    : cover (occ == DEPTH[IW-1:0]);
                end

        end else begin : g_id_bypass
            // the bypass path stores nothing: the output IS the input,
            // so a delivery and an acceptance are the same event and
            // the two accounting laws collapse. Same labels, same
            // claims -- capacity, then no invention, then payload.
            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset) begin
                    a_fifo_no_overflow  : assert (occ == {IW{1'b0}});
                    a_fifo_no_underflow : assert (insert == remove);
                    if (obs_valid)
                        a_fifo_beat : assert (obs_packet == in_packet);
                end

            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset) begin
                    c_fifo_deliver : cover (insert && remove);
                    // an offer standing unaccepted -- the case
                    // a_fifo_beat covers that a delivery would not reach
                    c_fifo_b2b     : cover (obs_valid && !out_ready);
                end
        end
    endgenerate
`endif

    // ----------------------------------------------------------------
    // handshake witnesses: live on every row, so no proof passes over
    // a link that never moves a beat or never stalls
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            c_fifo_xfer  : cover (obs_valid & out_ready);
            c_fifo_wait  : cover (obs_valid & ~out_ready);
            c_fifo_bp    : cover (~in_ready);
        end
`endif

endmodule

`default_nettype wire
