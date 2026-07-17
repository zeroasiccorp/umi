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

endmodule

`default_nettype wire
