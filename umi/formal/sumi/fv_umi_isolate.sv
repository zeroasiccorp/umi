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
 * - Proves the power-domain isolation buffer umi_isolate over both of
 *   its build-time arms, which are different circuits sharing a port
 *   list (umi_isolate.v:50-89):
 *
 *   ISO=1  la_isolo cells on every wire. Two laws:
 *            a_iso_clamp  isolate high drives the whole channel to
 *                         zero, VALID and READY included, so a
 *                         powered-down neighbour can neither offer nor
 *                         accept a beat
 *            a_iso_pass   isolate low passes every wire through
 *                         unchanged
 *   ISO=0  no cells at all -- a_iso_pass alone, unconditionally. That
 *          is already the whole claim for this arm: the channel passes
 *          through whatever isolate is doing, so a build that asks for
 *          isolation it did not compile in gets none.
 *
 * Purely combinational, so induction closes immediately; the value of
 * prove mode is the quantifier over every input word.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   isolate:prove         ISO=1, both laws, unbounded
 *   isolate:prove_iso0    ISO=0, passthrough, unbounded
 *   isolate:cover         witnesses: expect all reached
 *   isolate:fault_pass    must FAIL, a_iso_pass
 *   isolate:fault_clamp   must FAIL, a_iso_clamp
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_isolate #(
    parameter CW  = 32,
    parameter AW  = 64,
    parameter DW  = 64,
    parameter ISO = 1
) (
    input wire clk
);

    localparam PW = CW + AW + AW + DW;

    (* anyseq *) wire          isolate;
    (* anyseq *) wire          umi_ready;
    (* anyseq *) wire          umi_valid;
    (* anyseq *) wire [CW-1:0] umi_cmd;
    (* anyseq *) wire [AW-1:0] umi_dstaddr;
    (* anyseq *) wire [AW-1:0] umi_srcaddr;
    (* anyseq *) wire [DW-1:0] umi_data;

    wire          umi_ready_iso;
    wire          umi_valid_iso;
    wire [CW-1:0] umi_cmd_iso;
    wire [AW-1:0] umi_dstaddr_iso;
    wire [AW-1:0] umi_srcaddr_iso;
    wire [DW-1:0] umi_data_iso;

    umi_isolate #(
        .CW (CW), .AW (AW), .DW (DW), .ISO (ISO)
    ) dut (
        .isolate         (isolate),
        .umi_ready       (umi_ready),
        .umi_valid       (umi_valid),
        .umi_cmd         (umi_cmd),
        .umi_dstaddr     (umi_dstaddr),
        .umi_srcaddr     (umi_srcaddr),
        .umi_data        (umi_data),
        .umi_ready_iso   (umi_ready_iso),
        .umi_valid_iso   (umi_valid_iso),
        .umi_cmd_iso     (umi_cmd_iso),
        .umi_dstaddr_iso (umi_dstaddr_iso),
        .umi_srcaddr_iso (umi_srcaddr_iso),
        .umi_data_iso    (umi_data_iso)
    );

    // ----------------------------------------------------------------
    // observed outputs: the faults corrupt what the laws see, never the
    // DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_PASS
    // a wire that does not survive the transparent path
    wire [DW-1:0] obs_data = umi_data_iso ^ {DW{f_glitch}};
`else
    wire [DW-1:0] obs_data = umi_data_iso;
`endif

`ifdef FV_FAULT_CLAMP
    // a wire that keeps driving through the clamp
    wire obs_valid = umi_valid_iso | (isolate & f_glitch);
`else
    wire obs_valid = umi_valid_iso;
`endif

    wire [PW-1:0] in_bundle  = {umi_cmd, umi_dstaddr, umi_srcaddr, umi_data};
    wire [PW-1:0] out_bundle = {umi_cmd_iso, umi_dstaddr_iso,
                                umi_srcaddr_iso, obs_data};

    // ----------------------------------------------------------------
    // the two arms
    // ----------------------------------------------------------------
    generate
        if (ISO == 1) begin : g_iso
            always @(*) begin
                if (isolate) begin
                    a_iso_clamp : assert (!obs_valid && !umi_ready_iso
                                          && (out_bundle == {PW{1'b0}}));
                end else begin
                    a_iso_pass : assert ((obs_valid == umi_valid)
                                         && (umi_ready_iso == umi_ready)
                                         && (out_bundle == in_bundle));
                end
            end
        end else begin : g_noiso
            always @(*) begin
                // the cells are compiled out, so the channel is
                // transparent whatever isolate is doing
                a_iso_pass : assert ((obs_valid == umi_valid)
                                     && (umi_ready_iso == umi_ready)
                                     && (out_bundle == in_bundle));
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(*) begin
        // both sides of the clamp are really visited, and a live beat
        // really does cross the transparent path
        c_iso_clamped : cover (isolate);
        c_iso_open    : cover (!isolate);
        c_iso_beat    : cover (!isolate && umi_valid && umi_ready
                               && (umi_data != {DW{1'b0}}));
        // a non-zero payload standing at the clamp: the case that
        // separates a_iso_clamp from a link that happened to be idle
        c_iso_blocked : cover (isolate && umi_valid
                               && (umi_data != {DW{1'b0}}));
    end
`endif

endmodule

`default_nettype wire
