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
 * - Proves umi_data_aggregator keeps the SUMI handshake on the face it
 *   drives, and that a merged output carries the address of the FIRST
 *   beat that went into it.
 *
 * WHAT THE BLOCK IS. It merges consecutive mergeable beats into one
 * wider output beat, accumulating in a byte counter and emitting when
 * the counter reaches a full output word or when a passthrough beat
 * forces it out (umi_data_aggregator.v:263-264).
 *
 * THE ADDRESS LAW IS THE ONE WORTH HAVING. The output address is not
 * recomputed; it is the address registered from the beat that opened
 * the group (umi_data_aggregator.v:201-202):
 *
 *     assign umi_out_dstaddr = umi_in_dstaddr_r;
 *     assign umi_out_srcaddr = umi_in_srcaddr_r;
 *
 * a_agg_addr_first states that from the ports: while an output beat is
 * offered, its DSTADDR and SRCADDR are the ones the first accepted beat
 * of the current group carried. That matters beyond this block --
 * tl2umi reads its TileLink source and size back out of exactly this
 * address (tl2umi.v:263-264), so the field it reads is the first
 * beat's, not the last one's.
 *
 * WHAT IS PROVEN:
 *   RULE2_valid_hold / RULE3_*_stable  the output channel keeps
 *                     README 4.2, with the input constrained legal by
 *                     the same checker in its ASSUME face
 *   a_agg_addr_first  the output address is the first accepted beat's
 *
 * NOT PROVEN HERE: BYTE CONSERVATION. The claim a reader most wants --
 * that the bytes leaving equal the bytes accepted -- is not asserted.
 * It is the same accounting umi_fifoflex needed, and getting it right
 * there took a per-beat byte model and a pinned finding; doing it here
 * properly is its own piece of work rather than a line added to this
 * file. Saying that plainly is better than shipping a weaker law under
 * a name that sounds like the strong one.
 *
 * SCOPE. Bounded. One clock. The input is held to single-beat
 * messages that fit one output word, which is the shape the merge path
 * is built for.
 *
 * ROWS (tests/test_formal_sc.py):
 *   agg:bmc              the handshake and the address law, bounded
 *   agg:cover            witnesses: expect all reached
 *   agg:fault_addr       must FAIL, a_agg_addr_first
 *   agg:fault_data       must FAIL, RULE3_data_stable
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_data_aggregator #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64
) (
    input wire clk
);

`include "umi_messages.vh"

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // free stimulus
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

    umi_data_aggregator #(
        .CW (CW), .AW (AW), .DW (DW)
    ) dut (
        .clk (clk), .nreset (nreset),
        .umi_in_valid   (in_valid),
        .umi_in_cmd     (in_cmd),
        .umi_in_dstaddr (in_dstaddr),
        .umi_in_srcaddr (in_srcaddr),
        .umi_in_data    (in_data),
        .umi_in_ready   (in_ready),
        .umi_out_valid  (out_valid),
        .umi_out_cmd    (out_cmd),
        .umi_out_dstaddr(out_dstaddr),
        .umi_out_srcaddr(out_srcaddr),
        .umi_out_data   (out_data),
        .umi_out_ready  (out_ready)
    );

    // ----------------------------------------------------------------
    // the input face is constrained legal by the rule list the output
    // face is judged by
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (1)
    ) env_in (
        .clk (clk), .nreset (nreset),
        .valid (in_valid), .ready (in_ready),
        .cmd (in_cmd), .dstaddr (in_dstaddr),
        .srcaddr (in_srcaddr), .data (in_data)
    );

    wire [2:0] in_size = in_cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];
    wire [7:0] in_len  = in_cmd[UMI_LEN_MSB:UMI_LEN_LSB];
    wire [4:0] in_op   = in_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

    always @(*) begin
        // a single beat that fits one output word -- the shape the
        // merge path is built for
        m_agg_size : assume ((32'd1 << in_size) <= (DW / 8));
        m_agg_len  : assume (in_len == 8'd0);
        m_agg_op   : assume ((in_op == UMI_RESP_READ)
                             || (in_op == UMI_RESP_WRITE));
    end

    // ----------------------------------------------------------------
    // faults corrupt what the laws see, never the DUT
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_ADDR
    wire [AW-1:0] obs_dstaddr = out_dstaddr ^ {{(AW-1){1'b0}}, f_glitch};
`else
    wire [AW-1:0] obs_dstaddr = out_dstaddr;
`endif

`ifdef FV_FAULT_DATA
    wire [DW-1:0] obs_data = out_data ^ {{(DW-1){1'b0}}, f_glitch};
`else
    wire [DW-1:0] obs_data = out_data;
`endif

    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (0)
    ) chk_out (
        .clk (clk), .nreset (nreset),
        .valid (out_valid), .ready (out_ready),
        .cmd (out_cmd), .dstaddr (obs_dstaddr),
        .srcaddr (out_srcaddr), .data (obs_data)
    );

    // ----------------------------------------------------------------
    // the first beat of the group in progress, shadowed from the PORTS
    // ----------------------------------------------------------------
    wire in_fire  = in_valid & in_ready;
    wire out_fire = out_valid & out_ready;

    // The block's own notion of "first" is delimited by EOM on the
    // INPUT, not by the output handshake (umi_data_aggregator.v:196-197):
    //
    //     if (umi_in_cmd_commit)
    //         first <= (umi_in_cmd_eom | umi_in_cmd_write_resp);
    //
    // so it starts at 1 and returns to 1 after any beat that closes a
    // message or is a write response. Mirroring that here from the
    // ports is what makes the law below a check of the address path
    // rather than of a group model this harness invented.
    wire in_eom       = in_cmd[UMI_EOM_BIT];
    wire in_write_res = (in_op == UMI_RESP_WRITE);

    reg          agg_first;
    reg [AW-1:0] first_dstaddr, first_srcaddr;
    reg          latched;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            agg_first     <= 1'b1;
            latched       <= 1'b0;
            first_dstaddr <= {AW{1'b0}};
            first_srcaddr <= {AW{1'b0}};
        end else if (in_fire) begin
            if (agg_first) begin
                first_dstaddr <= in_dstaddr;
                first_srcaddr <= in_srcaddr;
                latched       <= 1'b1;
            end
            agg_first <= in_eom | in_write_res;
        end

    // ----------------------------------------------------------------
    // the address law
    // ----------------------------------------------------------------
    always @(posedge clk)
        if (nreset & f_past_exists & out_valid & latched)
            a_agg_addr_first : assert ((obs_dstaddr == first_dstaddr)
                                       && (out_srcaddr == first_srcaddr));

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_agg_in      : cover (in_fire);
            c_agg_out     : cover (out_fire);
            c_agg_stall   : cover (out_valid & ~out_ready);
            c_agg_backup  : cover (in_valid & ~in_ready);
            // a beat was accepted that did NOT open a group: the
            // merge really happened rather than every beat passing
            // straight through
            c_agg_merge   : cover (in_fire & ~agg_first);
            c_agg_payload : cover (out_fire & (obs_data != {DW{1'b0}}));
        end
`endif

endmodule

`default_nettype wire
