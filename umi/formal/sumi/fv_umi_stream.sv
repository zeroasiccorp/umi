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
 * - Proves the UMI-to-streaming bridge umi_stream keeps a legal
 *   handshake on all four of its faces at once: the two UMI faces
 *   against README.md section 4.2, and the two USI faces against the
 *   same two rules written out directly, since a USI beat carries
 *   DATA and LAST rather than a UMI packet and umi_handshake_checker
 *   does not fit it.
 *
 * ONE CLOCK. THIS IS THE SCOPE. umi_stream spans two domains --
 * umi_clk and usi_clk -- through two la_asyncfifo instances (S2MM and
 * MM2S). This harness ties the two clocks and the two resets and
 * proves the block in that configuration. It catches everything that
 * does not depend on the clock ratio: the handshake logic, the
 * pushback paths, the devicemode multiplexing. It says nothing about
 * true asynchrony, because metastability is not in the Verilog
 * semantics and the delay model that would make a synchroniser
 * meaningful does not exist in this directory yet. The async behaviour
 * is unverified here, not verified.
 *
 * BOUNDED, NOT UNBOUNDED. Bmc rows, for the reason fv_umi_fifo gives:
 * the FIFO pointers cross la_drsync registers no port shows, so
 * induction starts its step case from pointer states no trace reaches.
 *
 * WHAT IS PROVEN.
 *   RULE2_valid_hold / RULE3_*_stable   the UMI output face, with the
 *                     UMI input face constrained legal by the same
 *                     checker in its ASSUME face
 *   a_usi_out_hold    a USI offer is not withdrawn before it is
 *                     accepted
 *   a_usi_out_stable  DATA and LAST do not move under a standing USI
 *                     offer
 * The USI input face is assumed to obey the same two rules, which is
 * what any stream source is required to do.
 *
 * THE CONFIGURATION INPUTS MUST BE HELD. devicemode and the three
 * s2mm_* inputs are (* anyconst *) here -- the solver picks any value
 * but cannot move it mid-trace. That is not a convenience: in link
 * mode the UMI output payload is a combinational function of s2mm_cmd
 * and s2mm_dstaddr (umi_stream.v:227-228), so a controller that
 * rewrites them while umi_out_valid is standing changes the payload
 * under an unaccepted offer and breaks rule 3. Left free, this harness
 * reports exactly that, which is how the condition was found. Both
 * devicemode arms are still explored, one per trace, and c_str_device
 * and c_str_link witness that both are reached.
 *
 * WHAT IS NOT PROVEN, and no row here should be read as claiming it:
 * that a UMI packet arriving on the memory-mapped face comes out as
 * the right stream beats, or the reverse. That is a payload-carriage
 * claim across a width and framing change, it needs the byte
 * accounting umi_fifoflex also wants, and it is not attempted here.
 * This file is a handshake result and is labelled one.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   stream:bmc              all four faces, bounded
 *   stream:cover            witnesses: expect all reached
 *   stream:fault_valid      must FAIL, chk_umi_out.RULE2_valid_hold
 *   stream:fault_data       must FAIL, chk_umi_out.RULE3_data_stable
 *   stream:fault_usi_hold   must FAIL, a_usi_out_hold
 *   stream:fault_usi_stable must FAIL, a_usi_out_stable
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_stream #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64,
    parameter S2MM_DEPTH = 2,
    parameter MM2S_DEPTH = 2,
    parameter [5:0] RULE_EN = 6'h3F
) (
    input wire clk
);

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
    // free stimulus
    // ----------------------------------------------------------------
    // Configuration, not per-beat signals: held constant for the whole
    // trace. This is load-bearing and it is a statement about how the
    // block must be integrated, not a convenience. In link mode the UMI
    // output payload is driven combinationally from these inputs
    // (umi_stream.v:227-228, umi_out_cmd = devicemode ? resp_cmd_r :
    // s2mm_cmd), so a controller that moves s2mm_cmd, s2mm_dstaddr,
    // s2mm_srcaddr or devicemode while umi_out_valid is standing breaks
    // rule 3 at the output -- the payload changes under an offer that
    // has not been accepted. Left free, the harness reports exactly
    // that. Whoever drives these must hold them.
    (* anyconst *) wire          devicemode;
    (* anyconst *) wire [AW-1:0] s2mm_dstaddr;
    (* anyconst *) wire [AW-1:0] s2mm_srcaddr;
    (* anyconst *) wire [CW-1:0] s2mm_cmd;

    (* anyseq *) wire          umi_in_valid;
    (* anyseq *) wire [CW-1:0] umi_in_cmd;
    (* anyseq *) wire [AW-1:0] umi_in_dstaddr;
    (* anyseq *) wire [AW-1:0] umi_in_srcaddr;
    (* anyseq *) wire [DW-1:0] umi_in_data;
    (* anyseq *) wire          umi_out_ready;

    (* anyseq *) wire          usi_in_valid;
    (* anyseq *) wire          usi_in_last;
    (* anyseq *) wire [DW-1:0] usi_in_data;
    (* anyseq *) wire          usi_out_ready;

    wire          umi_in_ready;
    wire          umi_out_valid;
    wire [CW-1:0] umi_out_cmd;
    wire [AW-1:0] umi_out_dstaddr;
    wire [AW-1:0] umi_out_srcaddr;
    wire [DW-1:0] umi_out_data;
    wire          usi_out_valid;
    wire          usi_out_last;
    wire [DW-1:0] usi_out_data;
    wire          usi_in_ready;

    // both domains driven from the one clock and reset: see ONE CLOCK
    umi_stream #(
        .CW (CW), .AW (AW), .DW (DW),
        .S2MM_DEPTH (S2MM_DEPTH), .MM2S_DEPTH (MM2S_DEPTH)
    ) dut (
        .devicemode      (devicemode),
        .s2mm_dstaddr    (s2mm_dstaddr),
        .s2mm_srcaddr    (s2mm_srcaddr),
        .s2mm_cmd        (s2mm_cmd),
        .umi_nreset      (nreset),
        .umi_clk         (clk),
        .umi_in_valid    (umi_in_valid),
        .umi_in_cmd      (umi_in_cmd),
        .umi_in_dstaddr  (umi_in_dstaddr),
        .umi_in_srcaddr  (umi_in_srcaddr),
        .umi_in_data     (umi_in_data),
        .umi_in_ready    (umi_in_ready),
        .umi_out_valid   (umi_out_valid),
        .umi_out_cmd     (umi_out_cmd),
        .umi_out_dstaddr (umi_out_dstaddr),
        .umi_out_srcaddr (umi_out_srcaddr),
        .umi_out_data    (umi_out_data),
        .umi_out_ready   (umi_out_ready),
        .usi_clk         (clk),
        .usi_nreset      (nreset),
        .usi_out_valid   (usi_out_valid),
        .usi_out_last    (usi_out_last),
        .usi_out_data    (usi_out_data),
        .usi_out_ready   (usi_out_ready),
        .usi_in_valid    (usi_in_valid),
        .usi_in_last     (usi_in_last),
        .usi_in_data     (usi_in_data),
        .usi_in_ready    (usi_in_ready)
    );

    // ----------------------------------------------------------------
    // observed faces: the faults corrupt what the checkers and the USI
    // laws see, never the DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_VALID
    wire obs_umi_valid = umi_out_valid & ~f_glitch;
`else
    wire obs_umi_valid = umi_out_valid;
`endif

`ifdef FV_FAULT_DATA
    wire [DW-1:0] obs_umi_data = umi_out_data ^ {DW{f_glitch}};
`else
    wire [DW-1:0] obs_umi_data = umi_out_data;
`endif

`ifdef FV_FAULT_USI_HOLD
    wire obs_usi_valid = usi_out_valid & ~f_glitch;
`else
    wire obs_usi_valid = usi_out_valid;
`endif

`ifdef FV_FAULT_USI_STABLE
    wire [DW-1:0] obs_usi_data = usi_out_data ^ {DW{f_glitch}};
`else
    wire [DW-1:0] obs_usi_data = usi_out_data;
`endif

    // ----------------------------------------------------------------
    // the two UMI faces, both faces of one rule list
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (1),                      // environment: assume legal input
        .RULE_EN (RULE_EN)
    ) env_umi_in (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (umi_in_valid),
        .ready   (umi_in_ready),
        .cmd     (umi_in_cmd),
        .dstaddr (umi_in_dstaddr),
        .srcaddr (umi_in_srcaddr),
        .data    (umi_in_data)
    );

    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (0),                      // requirement: assert legal output
        .RULE_EN (RULE_EN)
    ) chk_umi_out (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (obs_umi_valid),
        .ready   (umi_out_ready),
        .cmd     (umi_out_cmd),
        .dstaddr (umi_out_dstaddr),
        .srcaddr (umi_out_srcaddr),
        .data    (obs_umi_data)
    );

    // ----------------------------------------------------------------
    // the two USI faces: rules 2 and 3 written out for a stream beat,
    // which carries DATA and LAST rather than a UMI packet
    // ----------------------------------------------------------------
    reg        usi_in_valid_q;
    reg        usi_in_last_q;
    reg [DW:0] usi_in_bundle_q;
    reg        usi_in_ready_q;
    always @(posedge clk) begin
        usi_in_valid_q  <= usi_in_valid;
        usi_in_ready_q  <= usi_in_ready;
        usi_in_bundle_q <= {usi_in_last, usi_in_data};
    end

    // the source is required to obey the same discipline as any UMI
    // driver: hold the offer, hold the payload
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset)
            if (usi_in_valid_q & ~usi_in_ready_q) begin
                assume (usi_in_valid);
                assume ({usi_in_last, usi_in_data} == usi_in_bundle_q);
            end

    reg        usi_out_valid_q;
    reg        usi_out_ready_q;
    reg [DW:0] usi_out_bundle_q;
    always @(posedge clk) begin
        usi_out_valid_q  <= obs_usi_valid;
        usi_out_ready_q  <= usi_out_ready;
        usi_out_bundle_q <= {usi_out_last, obs_usi_data};
    end

    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset)
            if (usi_out_valid_q & ~usi_out_ready_q) begin
                a_usi_out_hold : assert (obs_usi_valid);
                a_usi_out_stable : assert ({usi_out_last, obs_usi_data}
                                           == usi_out_bundle_q);
            end

    // ----------------------------------------------------------------
    // witnesses: no face is passing on a link that never moves a beat
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            c_str_umi_xfer : cover (obs_umi_valid & umi_out_ready);
            c_str_umi_wait : cover (obs_umi_valid & ~umi_out_ready);
            c_str_usi_xfer : cover (obs_usi_valid & usi_out_ready);
            c_str_usi_wait : cover (obs_usi_valid & ~usi_out_ready);
            c_str_usi_last : cover (obs_usi_valid & usi_out_ready
                                    & usi_out_last);
            c_str_umi_bp   : cover (~umi_in_ready);
            c_str_usi_bp   : cover (~usi_in_ready);
            // both operating modes really are explored
            c_str_device   : cover (devicemode & obs_usi_valid);
            c_str_link     : cover (~devicemode & obs_umi_valid);
        end
`endif

endmodule

`default_nettype wire
